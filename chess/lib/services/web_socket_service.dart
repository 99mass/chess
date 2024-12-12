import 'dart:async';
import 'dart:convert';
import 'package:chess/model/friend_model.dart';
import 'package:chess/model/invitation_model.dart';
import 'package:chess/screens/game_board_screen.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/api_link.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:flutter/material.dart';
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

  void _handleMessage(
    dynamic message,
    BuildContext? context,
  ) {
    try {
      final Map<String, dynamic> data = json.decode(message);

      switch (data['type']) {
        case 'online_users':
          final List<UserProfile> onlineUsers =
              (json.decode(data['content']) as List)
                  .map((userJson) => UserProfile.fromJson(userJson))
                  .toList();

          final uniqueUsers = onlineUsers.toSet().toList();
          _onlineUsersController.add(uniqueUsers);
          break;
        case 'invitation':
          final invitation =
              InvitationMessage.fromJson(json.decode(data['content']));
          _invitationController.add(invitation);
          break;
        case 'game_start':
          if (context != null) {
            final gameData = json.decode(data['content']);
            _navigateToGameBoard(context, gameData);
          }
          break;

        case 'invitation_rejected':
          if (context != null) {
            final invitation =
                InvitationMessage.fromJson(json.decode(data['content']));
            _handleInvitationRejection(context, invitation);
          }
          break;
        case 'invitation_cancel':
          if (context != null) {
            final invitation =
                InvitationMessage.fromJson(json.decode(data['content']));
            _handleInvitationCancel(context, invitation);
          }
          break;

        default:
          print('Unhandled message type: ${data['type']}');
      }
    } catch (e) {
      print('Error handling WebSocket message: $e');
    }
  }

  void sendGameInvitation(BuildContext context,
      {required UserProfile currentUser, required UserProfile toUser}) {
    if (!_isConnected) {
      print('WebSocket not connected');
      return;
    }

    final invitation = InvitationMessage(
      type: 'invitation_send',
      fromUserId: currentUser.id,
      fromUsername: currentUser.userName,
      toUserId: toUser.id,
      toUsername: toUser.userName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final invitationJson = json.encode({
      'type': 'invitation_send',
      'content': json.encode(invitation.toJson())
    });

    sendMessage(invitationJson);
  }

  void acceptInvitation(UserProfile currentUser, InvitationMessage invitation) {
    final acceptMessage = InvitationMessage(
      type: 'invitation_accept',
      fromUserId: currentUser.id,
      fromUsername: currentUser.userName,
      toUserId: invitation.fromUserId,
      toUsername: invitation.fromUsername,
      roomId: invitation.roomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final acceptJson = json.encode({
      'type': 'invitation_accept',
      'content': json.encode(acceptMessage.toJson())
    });

    sendMessage(acceptJson);
  }

  void rejectInvitation(UserProfile currentUser, InvitationMessage invitation) {
    final rejectMessage = InvitationMessage(
      type: 'invitation_reject',
      fromUserId: currentUser.id,
      fromUsername: currentUser.userName,
      toUserId: invitation.fromUserId,
      toUsername: invitation.fromUsername,
      roomId: invitation.roomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final rejectJson = json.encode({
      'type': 'invitation_reject',
      'content': json.encode(rejectMessage.toJson())
    });

    sendMessage(rejectJson);
  }

  void sendInvitationCancel(InvitationMessage invitation) {
    final cancelMessage = InvitationMessage(
      type: 'invitation_cancel',
      fromUserId: invitation.fromUserId,
      fromUsername: invitation.fromUsername,
      toUserId: invitation.toUserId,
      toUsername: invitation.toUsername,
      roomId: invitation.roomId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
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
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Game Invitation'),
          content: Text('${invitation.fromUsername} invites you to play chess'),
          actions: [
            TextButton(
              child: const Text('Accept'),
              onPressed: () {
                acceptInvitation(currentUser, invitation);
                Navigator.of(dialogContext).pop(true);
              },
            ),
            TextButton(
              child: const Text('Reject'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                rejectInvitation(currentUser, invitation);
              },
            ),
          ],
        );
      },
    );
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

  void _navigateToGameBoard(
    BuildContext context,
    Map<String, dynamic> gameData,
  ) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const GameBoardScreen(
            // roomId: gameData['room_id'],
            // isWhitePlayer: gameData['white_player'] == currentUser.userName,
            // opponent: gameData['white_player'] == currentUser.userName
            //     ? gameData['black_player']
            //     : gameData['white_player'],
            ),
      ),
    );
  }

  void _handleInvitationRejection(
      BuildContext context, InvitationMessage invitation) {
    // Fermer l'écran d'attente et afficher un message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invitation.fromUsername} rejected your invitation'),
        duration: const Duration(seconds: 5),
      ),
    );
    Timer(const Duration(seconds: 5), () {});
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MainMenuScreen(),
        ));
  }

  void _handleInvitationCancel(
      BuildContext context, InvitationMessage invitation) {
    // Fermer l'écran d'attente et afficher un message
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invitation.toUsername} canceled the invitation'),
        duration: const Duration(seconds: 5),
      ),
    );
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

  void disposeInvitationStream() {
    _invitationController.close();
    _invitationController = StreamController<InvitationMessage>.broadcast();
  }
}
