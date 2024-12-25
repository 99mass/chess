import 'dart:convert';

import 'package:chess/model/friend_model.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:flutter/material.dart';
import 'package:chess/screens/waiting_room_screen.dart';
import 'package:provider/provider.dart';

class FriendListScreen extends StatefulWidget {
  const FriendListScreen({super.key});

  @override
  State<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen> {
  late GameProvider _gameProvider;
  late WebSocketService _webSocketService;
  List<UserProfile> onlineUsers = [];

  @override
  void initState() {
    super.initState();

    // Initialize WebSocket connection
    _webSocketService = WebSocketService();

    _gameProvider = Provider.of<GameProvider>(context, listen: false);

    // Connect WebSocket
    _webSocketService.connectWebSocket(context).then((_) {
      _webSocketService
          .sendMessage(json.encode({'type': 'request_online_users'}));
    });

    // Listen to online users stream
    _gameProvider.onlineUsersStream.listen((users) { });

    // Handle invitations
    _gameProvider.invitationsStream.listen((invitations) {
      if (invitations.isNotEmpty) {
        final latestInvitation = invitations.last;
        _webSocketService.handleInvitationInteraction(
            context, _gameProvider.user, latestInvitation);
      }
    }, onError: (error) {
      print('Erreur dans le flux d\'invitations : $error');
    });
  }

  @override
  void dispose() {
    _gameProvider.clearInvitations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: const Text('Friend List'),
        backgroundColor: Colors.amber[700],
      ),
      body: StreamBuilder<List<UserProfile>>(
        stream: _gameProvider.onlineUsersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          onlineUsers = [];
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No other users online',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          for (var user in snapshot.data!) {
            if (_gameProvider.user.id != user.id) {
              if (!user.isInRoom) {
                onlineUsers.add(user);
              }
            }
          }

          if (onlineUsers.isEmpty) {
            return const Center(
              child: Text(
                'No other users online',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: onlineUsers.length,
            itemBuilder: (context, index) {
              return _buildFriendItem(context, onlineUsers[index]);
            },
          );
        },
      ),
    );
  }

  Widget _buildFriendItem(BuildContext context, UserProfile user) {
    return GestureDetector(
      onTap: () {
        _gameProvider.createInvitation(
            toUser: user, fromUser: _gameProvider.user);

        // Send game invitation
        _webSocketService.sendGameInvitation(context,
            toUser: user, currentUser: _gameProvider.user);
        _gameProvider.setOpponentUsername(username: user.userName);

        // Navigate to waiting room
        Navigator.of(context).pop(true);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const WaitingRoomScreen(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.amber[700]!, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: AssetImage('assets/avatar.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      alignment: Alignment.center,
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.green[700],
                        shape: BoxShape.circle,
                        border: Border.all(width: 2, color: Colors.green[700]!),
                      ),
                      child: const Center(
                        child: Text(
                          '1',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    user.userName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.white,
              size: 30,
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}
