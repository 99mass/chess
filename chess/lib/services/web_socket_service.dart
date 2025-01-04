import 'dart:async';
import 'dart:convert';
import 'dart:math' as Math;

import 'package:chess/constant/constants.dart';
import 'package:chess/screens/friend_list_screen.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/custom_page_route.dart';
import 'package:chess/widgets/custom_alert_dialog.dart';
import 'package:chess/widgets/custom_snack_bar.dart';
import 'package:squares/squares.dart';
import 'package:chess/model/friend_model.dart';
import 'package:chess/model/invitation_model.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/game_board_screen.dart';
import 'package:chess/utils/api_link.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chess/services/user_service.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;

  var _invitationController = StreamController<InvitationMessage>.broadcast();

  final _moveController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get moveStream => _moveController.stream;

  Timer? _reconnectTimer;
  bool _isConnected = false;

  bool _isReconnecting = false;
  static const int maxReconnectAttempts = 5;
  int _reconnectAttempts = 0;

  bool get isConnected => _isConnected;
  Stream<InvitationMessage> get invitationStream =>
      _invitationController.stream;

  Future<void> connectWebSocket(BuildContext? context) async {
    // Si déjà connecté, ne rien faire
    if (_isConnected && _channel != null) {
      return;
    }

    final user = await SharedPreferencesStorage.instance.getUserLocally();
    if (user == null || user.userName.isEmpty) {
      print('No user connected');
      return;
    }

    final wsUrl = '$socketLink?username=${user.userName}';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // asBroadcastStream() pour permettre plusieurs écouteurs
      _channel!.stream.asBroadcastStream().listen(
        (message) {
          _handleMessage(message, context);
        },
        onDone: () {
          _isConnected = false;
          _onConnectionClosed(context);
        },
        onError: (error) {
          _isConnected = false;
          print('WebSocket error: $error');
          _reconnect(context);
        },
      );

      await UserService.updateUserOnlineStatus(user.userName, true);
      _isConnected = true;

      if (_isConnected) {
        sendMessage(json.encode({'type': 'request_online_users'}));
      }

      print('WebSocket connected for ${user.userName}');
    } catch (e) {
      _isConnected = false;
      print('Error connecting WebSocket: $e');
      _reconnect(context);
    }
  }

  Future<void> ensureConnection(BuildContext context) async {
    if (_isReconnecting) return;

    if (!_isConnected || _channel == null || _channel?.closeCode != null) {
      _isReconnecting = true;

      while (_reconnectAttempts < maxReconnectAttempts && !_isConnected) {
        try {
          await connectWebSocket(context);
          if (_isConnected) {
            _reconnectAttempts = 0;
            break;
          }
          _reconnectAttempts++;
          await Future.delayed(
              Duration(seconds: Math.min(5, _reconnectAttempts * 2)));
        } catch (e) {
          print('WebSocket reconnection attempt failed: $e');
        }
      }

      _isReconnecting = false;
    }
  }

  Future<bool> initializeConnection(BuildContext context) async {
    try {
      await ensureConnection(context);
      if (_isConnected) {
        sendMessage(json.encode({'type': 'request_online_users'}));
        return true;
      }
      return false;
    } catch (e) {
      print('Error initializing WebSocket connection: $e');
      return false;
    }
  }

  Future<void> _handleMessage(
    dynamic message,
    BuildContext? context,
  ) async {
    try {
      final Map<String, dynamic> data = json.decode(message);

      switch (data['type']) {
        case 'online_users':
          final List<UserProfile> onlineUsers =
              (json.decode(data['content']) as List)
                  .map((userJson) => UserProfile.fromJson(userJson))
                  .toList();

          if (context != null) {
            Provider.of<GameProvider>(context, listen: false)
                .updateOnlineUsers(onlineUsers);
          }
          break;

        case 'invitation':
          final invitation =
              InvitationMessage.fromJson(json.decode(data['content']));

          if (context != null) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.addInvitation(invitation);
            gameProvider.setCancelWaintingRoom(value: false);
            gameProvider.setInvitationTimeOut(value: false);
          }
          break;

        case 'invitation_rejected':
          final invitation =
              InvitationMessage.fromJson(json.decode(data['content']));

          if (context != null) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.handleInvitationRejection(context, invitation);
            gameProvider.setInvitationRejct(value: true);
            gameProvider.removeInvitation(invitation);
          }
          break;

        case 'invitation_cancelled':
          if (context != null) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.setCancelWaintingRoom(value: true);
          }
          break;

        case 'invitation_timeout':
          if (context != null && context.mounted) {
            final invitation = json.decode(data['content']);
            try {
              final gameProvider =
                  Provider.of<GameProvider>(context, listen: false);

              if (gameProvider.user.id == invitation['from_user_id']) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => CustomAlertDialog(
                      titleMessage: "Demande expirée !",
                      subtitleMessage:
                          "La demande d'invitation a expirée. Veuillez réessayer.",
                      typeDialog: 0,
                      onOk: () {
                        Navigator.of(context).pop();
                        Navigator.pushReplacement(
                          context,
                          CustomPageRoute(child: const FriendListScreen()),
                        );
                      },
                    ),
                  );
                });
              } else {
                gameProvider.setInvitationTimeOut(value: true);
              }
            } catch (e) {
              print('Error processing invitation timeout: $e');
            }
          }
          break;
        // -------------Game -----------------
        case 'game_start':
          if (context != null && context.mounted) {
            final gameData = json.decode(data['content']);

            try {
              final gameProvider =
                  Provider.of<GameProvider>(context, listen: false);

              gameProvider.initializeMultiplayerGame(gameData);
              gameProvider.setInvitationCancel(value: false);
              gameProvider.setIsloading(true);

              Navigator.of(context).push(
                CustomPageRoute2(child: const GameBoardScreen()),
              );
            } catch (e) {
              print('Error initializing game: $e');
              showCustomSnackBarBottom(
                  context, 'Impossible de commencer la partie');
            }
          }
          break;

        case 'room_closed':
          if (context != null) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);

            gameProvider.setIsloading(false);
            gameProvider.setIsGameEnd(value: true);
            gameProvider.setOnWillPop(value: true);
            gameProvider.setCurrentInvitation();
            gameProvider.setFriendsMode(value: false);

            if (context.mounted) {
              Future.microtask(() {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext dialogContext) => CustomAlertDialog(
                    titleMessage: "Partie Terminée",
                    subtitleMessage:
                        'Vous avez gagné, Votre adversaire a abandonné la partie.',
                    typeDialog: 0,
                  ),
                );
              });
            }
          }
          break;

        case 'game_move':
          if (context != null && context.mounted) {
            final moveData = json.decode(data['content']);
            try {
              final gameProvider =
                  Provider.of<GameProvider>(context, listen: false);

              // Vérifier si le move vient de l'adversaire
              if (moveData['fromUserId'] != gameProvider.user.id) {
                gameProvider.handleOpponentMove(moveData);
                gameProvider.setIsMyTurn(value: true);
                gameProvider.setIsOpponentTurn(value: false);
              }
            } catch (e) {
              print('Error processing game move: $e');
            }
          }
          break;

        case 'time_update':
          if (context != null && context.mounted) {
            final timer = json.decode(data['content']);
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.setLastWhiteTime(value: timer['whiteTime']);
            gameProvider.setLastBlackTime(value: timer['blackTime']);
            gameProvider.setInvitationCancel(value: false);
          }
          break;

        case 'game_over':
          if (context != null && context.mounted) {
            final gameOverData = json.decode(data['content']);
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);

            if (context.mounted) {
              gameProvider.setIsloading(false);
              String message = gameOverData['winnerId'] == gameProvider.user.id
                  ? 'Félicitations, vous avez gagné la partie, le temps est terminé !'
                  : 'Dommage, vous avez perdu la partie, le temps est terminé !';
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext dialogContext) => CustomAlertDialog(
                  titleMessage: "Partie Terminée",
                  subtitleMessage: message,
                  typeDialog: 0,
                  logo: gameOverData['winnerId'] == gameProvider.user.id
                      ? 'assets/icons8_crown.png'
                      : 'assets/icons8_lose.png',
                ),
              );
              gameProvider.setCurrentInvitation();
              gameProvider.setFriendsMode(value: false);
              gameProvider.setOnWillPop(value: true);
            }
          }
          break;

        case 'game_over_checkmate':
          final gameOverData = json.decode(data['content']);
          if (context != null && context.mounted) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);

            if (context.mounted) {
              gameProvider.setIsloading(false);

              String message = '';
              String reason = '';
              if (gameOverData['winner'] == "Draw") {
                message = gameOverData['reason'];
                // victoires/défaites
              } else if ((gameOverData['winner'] == "Black" &&
                      gameProvider.playerColor == PlayerColor.black) ||
                  (gameOverData['winner'] == "White" &&
                      gameProvider.playerColor == PlayerColor.white)) {
                reason = gameOverData['reason'];

                message = reason.isEmpty
                    ? 'Félicitations ! Vous avez gagné la partie !'
                    : 'Félicitations ! Vous avez gagné $reason !';
              } else {
                reason = gameOverData['reason'];
                message = reason.isEmpty
                    ? 'Dommage, vous avez perdu la partie !'
                    : 'Dommage, votre adversaire a gagné $reason !';
              }

              // Déterminer le logo approprié
              String logo = gameOverData['winner'] == "Draw"
                  ? 'assets/chess_logo.png'
                  : ((gameOverData['winner'] == "Black" &&
                              gameProvider.playerColor == PlayerColor.black) ||
                          (gameOverData['winner'] == "White" &&
                              gameProvider.playerColor == PlayerColor.white)
                      ? 'assets/icons8_crown.png'
                      : 'assets/icons8_lose.png');

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext dialogContext) => CustomAlertDialog(
                  titleMessage: "Partie Terminée",
                  subtitleMessage: message,
                  typeDialog: 0,
                  logo: logo,
                ),
              );

              // Réinitialiser l'état du jeu
              gameProvider.setCurrentInvitation();
              gameProvider.setFriendsMode(value: false);
              gameProvider.setOnWillPop(value: true);
            }
          }
          break;

        case 'public_game_timeout':
          final timeOutData = json.decode(data['content']);

          if (context != null && context.mounted) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.setOnWillPop(value: true);
            showCustomSnackBarTop(context, timeOutData['message']);
            Navigator.pushReplacement(
              context,
              CustomPageRoute(child: const MainMenuScreen()),
            );
          }
          break;
        case 'public_queue_leave':
          final datas = json.decode(data['content']);
          if (context != null && context.mounted) {
            showCustomSnackBarTop(context, datas['message']);
          }
          break;
        case 'error':
          if (context != null && context.mounted) {
            final errorData = json.decode(data['content']);
            print('Error: ${errorData['message']}');
            showCustomSnackBarTop(context, errorData['message']);
          }
          break;
        default:
          print('Unhandled message type: ${data['type']}');
      }
    } catch (e) {
      print('❌ Error in Message Handling: $e');
    }
  }

  void sendGameInvitation(BuildContext context,
      {required UserProfile currentUser, required UserProfile toUser}) {
    if (!_isConnected) {
      print('❌ WebSocket Disconnected');
      showCustomSnackBarBottom(
          context, 'Erreur de réseau. Veuillez vous reconnecter.');
      return;
    }

    final invitation = InvitationMessage(
      type: 'invitation_send',
      fromUserId: currentUser.id,
      fromUsername: currentUser.userName,
      toUserId: toUser.id,
      toUsername: toUser.userName,
    );

    final invitationJson = json.encode({
      'type': 'invitation_send',
      'content': json.encode(invitation.toJson())
    });

    sendMessage(invitationJson);

    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.removeInvitation(invitation);
    print('✅ Invitation Sent Successfully');
  }

  void acceptInvitation(UserProfile currentUser, InvitationMessage invitation) {
    final acceptMessage = InvitationMessage(
      type: 'invitation_accept',
      fromUserId: currentUser.id,
      fromUsername: currentUser.userName,
      toUserId: invitation.fromUserId,
      toUsername: invitation.fromUsername,
      roomId: invitation.roomId,
    );

    final acceptJson = json.encode({
      'type': 'invitation_accept',
      'content': json.encode(acceptMessage.toJson())
    });

    sendMessage(acceptJson);
  }

  void rejectInvitation(BuildContext context, UserProfile currentUser,
      InvitationMessage invitation) {
    final rejectMessage = InvitationMessage(
      type: 'invitation_reject',
      fromUserId: currentUser.id,
      fromUsername: currentUser.userName,
      toUserId: invitation.fromUserId,
      toUsername: invitation.fromUsername,
      roomId: invitation.roomId,
    );

    final rejectJson = json.encode({
      'type': 'invitation_reject',
      'content': json.encode(rejectMessage.toJson())
    });

    sendMessage(rejectJson);
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.setInvitationCancel(value: false);
  }

  void sendInvitationCancel(InvitationMessage invitation) {
    final cancelMessage = InvitationMessage(
      type: 'invitation_cancel',
      fromUserId: invitation.fromUserId,
      fromUsername: invitation.fromUsername,
      toUserId: invitation.toUserId,
      toUsername: invitation.toUsername,
      roomId: invitation.roomId,
    );

    final cancelJson = json.encode({
      'type': 'invitation_cancel',
      'content': json.encode(cancelMessage.toJson())
    });
    sendMessage(cancelJson);
  }

  // Méthode pour gérer les invitations avec des interactions UI
  void handleInvitationInteraction(BuildContext context,
      UserProfile currentUser, InvitationMessage invitation) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.setInvitationCancel(value: false);

    switch (invitation.type) {
      case 'invitation_send':
        _showInvitationDialog(context, currentUser, invitation);
        break;
      case 'invitation_accept':
        _handleInvitationAccepted(context, invitation);
        break;
    }
  }

  bool _isDialogShowing = false;

  void _showInvitationDialog(BuildContext context, UserProfile currentUser,
      InvitationMessage invitation) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDialogShowing) {
        _isDialogShowing = true;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return CustomAlertDialog(
              titleMessage: "Invitation!",
              subtitleMessage:
                  '${invitation.fromUsername} vous invite à jouer une partie ?',
              typeDialog: 2,
              onAccept: () {
                if (!gameProvider.cancelWaintingRoom &&
                    !gameProvider.invitationTimeOut) {
                  acceptInvitation(currentUser, invitation);
                }
                if (gameProvider.cancelWaintingRoom) {
                  showCustomSnackBarBottom(context,
                      ' ${invitation.fromUsername} a annulée l\'invitation!');
                  gameProvider.removeInvitation(invitation);
                }
                if (gameProvider.invitationTimeOut) {
                  showCustomSnackBarBottom(
                      context, 'Invitation annulée, le temps est ecoulé!');
                  gameProvider.removeInvitation(invitation);
                }
                gameProvider.setCancelWaintingRoom(value: false);
                gameProvider.setInvitationTimeOut(value: false);
                _isDialogShowing = false;
              },
              onCancel: () {
                if (!gameProvider.cancelWaintingRoom &&
                    !gameProvider.invitationTimeOut) {
                  rejectInvitation(context, currentUser, invitation);
                }
                gameProvider.setCancelWaintingRoom(value: false);
                gameProvider.setInvitationTimeOut(value: false);
                gameProvider.removeInvitation(invitation);
                _isDialogShowing = false;
              },
            );
          },
        );
      }
      ;
    });
  }

  void _handleInvitationAccepted(
      BuildContext context, InvitationMessage invitation) {
    showCustomSnackBarBottom(
        context, '${invitation.fromUsername} a accepté votre invitation');
  }

  void leaveRoom(UserProfile currentUser) {
    if (!_isConnected) {
      print('WebSocket not connected');
      return;
    }

    final leaveMessage = {
      'type': 'room_leave',
      'content': json.encode({
        'username': currentUser.userName,
      }),
    };

    sendMessage(json.encode(leaveMessage));
  }

  void _onConnectionClosed(BuildContext? context) {
    print('WebSocket disconnected');
    _isConnected = false;
    _reconnect(context);
  }

  void _reconnect(BuildContext? context) {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected) {
        print('Attempting to reconnect...');
        await connectWebSocket(context);
        if (_isConnected) {
          timer.cancel();
        }
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> disconnect() async {
    final user = await SharedPreferencesStorage.instance.getUserLocally();

    if (user != null && user.userName.isNotEmpty) {
      try {
        await UserService.updateUserOnlineStatus(user.userName, false);
      } catch (e) {
        print('Error updating user status: $e');
      }
    }

    _cleanup();
  }

  // Method to send a message via WebSocket
  void sendMessage(String message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(message);
    }
  }

// ---------Game Move------------
  final List<Function(String)> _messageListeners = [];

  void addMessageListener(Function(String) listener) {
    _messageListeners.add(listener);
  }

  void removeMessageListener(Function(String) listener) {
    _messageListeners.remove(listener);
  }

// Add this method to your WebSocket service
  void sendGameMove(GameProvider gameProvider, Move move) {
    // Convert squares Move to string move
    String moveString = '${move.from}${move.to}';

    final moveMessage = {
      'type': 'game_move',
      'content': json.encode({
        'gameId': gameProvider.gameId,
        'move': moveString,
        'positionFen': gameProvider.gameModel?.positonFen ?? '',
        'isWhitesTurn': !(gameProvider.gameModel?.isWhitesTurn ?? true),
      }),
    };

    sendMessage(json.encode(moveMessage));
  }

  void disposeInvitationStream() {
    _invitationController.close();
    _invitationController = StreamController<InvitationMessage>.broadcast();
  }

  void _cleanup() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
  }

  void cleanupResources() {
    _cleanup();
    disconnect();
  }
}
