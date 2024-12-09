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
  final WebSocketService _webSocketService = WebSocketService();
  List<String> _onlineUsers = [];

  @override
  void initState() {
    super.initState();
    _webSocketService.connectWebSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_webSocketService.isConnected) {
        print('Connecté au WebSocket');
        _webSocketService.onlineUsersStream.listen((users) {
          print('Données reçues dans FriendListScreen: $users');
          setState(() {
            _onlineUsers = users;
          });
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: const Text(
          'Friend List',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.amber[700],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _onlineUsers.length,
        itemBuilder: (context, index) {
          return gameProvider.user.userName != _onlineUsers[index]
              ? _buildFriendItem(_onlineUsers[index])
              : Container();
        },
      ),
    );
  }

  Widget _buildFriendItem(String userName) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                WaitingRoomScreen(friendId: userName.hashCode),
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
                    userName,
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
