import 'dart:async';
import 'dart:convert';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/helper.dart';
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
  StreamController<List<UserProfile>> _onlineUsersController =
      StreamController<List<UserProfile>>.broadcast();

  var _invitationController = StreamController<InvitationMessage>.broadcast();

  final _moveController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get moveStream => _moveController.stream;

  Timer? _reconnectTimer;
  bool _isConnected = false;

  Stream<List<UserProfile>> get onlineUsersStream =>
      _onlineUsersController.stream;
  bool get isConnected => _isConnected;
  Stream<InvitationMessage> get invitationStream =>
      _invitationController.stream;

  Future<void> connectWebSocket(BuildContext? context) async {
    // Retrieve the user from SharedPreferences
    final user = await SharedPreferencesStorage.instance.getUserLocally();

    if (user == null || user.userName.isEmpty) {
      print('No user connected');
      return;
    }

    // URL of your WebSocket
    final wsUrl = '$socketLink?username=${user.userName}';

    try {
      // Establish the WebSocket connection
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Update the online status on the server
      await UserService.updateUserOnlineStatus(user.userName, true);

      // Listen to messages
      _channel!.stream.listen(
        (message) {
          _handleMessage(message, context);
        },
        onDone: () => _onConnectionClosed(context),
        onError: (error) {
          print('WebSocket error: $error');
          _reconnect(context);
        },
      );

      _isConnected = true;

      if (_isConnected) {
        sendMessage(json.encode({'type': 'request_online_users'}));
      }

      print('WebSocket connected for ${user.userName}');
    } catch (e) {
      print('Error connecting WebSocket: $e');
      _reconnect(context);
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
          }
          break;

        case 'invitation_rejected':
          final invitation =
              InvitationMessage.fromJson(json.decode(data['content']));

          if (context != null) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.setInvitationCancel(value: true);
            gameProvider.removeInvitation(invitation);
            gameProvider.handleInvitationRejection(context, invitation);
          }
          break;

        case 'invitation_cancel':
          final invitation =
              InvitationMessage.fromJson(json.decode(data['content']));

          if (context != null) {
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);
            gameProvider.handleInvitationCancellation(context, invitation);
            gameProvider.setInvitationCancel(value: true);
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
                MaterialPageRoute(
                  builder: (context) => const GameBoardScreen(),
                ),
              );
            } catch (e) {
              print('Error initializing game: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to start game try again')),
              );
            }
          }
          break;

        case 'room_closed':
          if (context != null) {
            final Map<String, dynamic> roomData = json.decode(data['content']);
            final fromUsername = roomData['fromUsername'];

            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);

            if (!gameProvider.exitGame) {
              gameProvider.setIsloading(false);
              gameProvider.setExitGame(value: true);
              gameProvider.setGameModel();
              gameProvider.setCurrentInvitation();
              gameProvider.setFriendsMode(value: false);
              gameProvider.setCompturMode(value: false);

              Future.microtask(() {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$fromUsername has left the game.'),
                  ));
                  Timer(const Duration(seconds: 2), () {});
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MainMenuScreen(),
                    ),
                  );
                }
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
              String message = '${gameOverData['winner']} wins by timeout!';
              showDialogGameOver(context, message);
              gameProvider.setCurrentInvitation();
              gameProvider.setFriendsMode(value: false);
              gameProvider.setOnWillPop(value: true);
            }
          }
          break;

        case 'game_over_checkmate':
          if (context != null && context.mounted) {
            final gameOverData = json.decode(data['content']);
            // print('📦📦 Received Game Checkmate Data: $gameOverData');
            final gameProvider =
                Provider.of<GameProvider>(context, listen: false);

            if (context.mounted) {
              gameProvider.setIsloading(false);
              String message = '${gameOverData['message']}';
              showDialogGameOver(context, message,
                  score: gameOverData['score']);
              gameProvider.setCurrentInvitation();
              gameProvider.setFriendsMode(value: false);
              gameProvider.setOnWillPop(value: true);
            }
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network Error. Please reconnect.')));
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

  void _showInvitationDialog(BuildContext context, UserProfile currentUser,
      InvitationMessage invitation) {
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return Consumer<GameProvider>(
            builder: (context, gameProvider, child) {
              // Vérifier si l'invitation a été annulée
              if (gameProvider.invitationCancel) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  gameProvider.removeInvitation(invitation);
                  gameProvider.setInvitationCancel(value: false);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Time out Invitation canceled!'),
                      duration: Duration(seconds: 5),
                    ),
                  );
                  if (Navigator.of(dialogContext).canPop()) {
                    Navigator.of(dialogContext).pop();
                  }
                });
              }

              return AlertDialog(
                title: const Text('Game Invitation'),
                content: Text(
                    '${invitation.fromUsername} invites you to play chess'),
                actions: [
                  TextButton(
                    child: const Text('Accept'),
                    onPressed: () {
                      acceptInvitation(currentUser, invitation);
                      gameProvider.setInvitationCancel(value: false);
                      Navigator.of(dialogContext).pop(true);
                    },
                  ),
                  TextButton(
                    child: const Text('Reject'),
                    onPressed: () {
                      gameProvider.setInvitationCancel(value: false);
                      Navigator.of(dialogContext).pop();
                      rejectInvitation(context, currentUser, invitation);
                      gameProvider.removeInvitation(invitation);
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    }
  }

  void _handleInvitationAccepted(
      BuildContext context, InvitationMessage invitation) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invitation.fromUsername} accepted your invitation'),
        duration: const Duration(seconds: 5),
      ),
    );
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
    // Cancel the previous timer if it exists
    _reconnectTimer?.cancel();

    // Attempt to reconnect every 5 seconds
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected) {
        print('Attempting to reconnect...');
        await connectWebSocket(context);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> disconnect() async {
    final user = await SharedPreferencesStorage.instance.getUserLocally();

    if (user != null && user.userName.isNotEmpty) {
      await UserService.updateUserOnlineStatus(user.userName, false);
    }

    // Close the WebSocket connection
    _channel?.sink.close();
    _isConnected = false;

    // Close the online users stream
    await _onlineUsersController.close();

    _onlineUsersController = StreamController<List<UserProfile>>.broadcast();
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
}
