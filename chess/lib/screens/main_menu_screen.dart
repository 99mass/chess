import 'package:chess/screens/friend_list_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/game_time_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MainMenuScreenState createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  late WebSocketService _webSocketService;

  @override
  void initState() {
    super.initState();

    // Initialise WebSocketService
    _webSocketService = WebSocketService();
    _webSocketService.connectWebSocket(context);

    // Load user from game provider
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.loadUser();

    // Listen to invitations
    _webSocketService.invitationStream.listen((invitation) {
      _webSocketService.handleInvitationInteraction(
          context, gameProvider.user, invitation);
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
      backgroundColor: Colors.black54,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 300,
              height: 200,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/knight_piece.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                _buildMenuButton(
                  'PLAYER vs COMPUTER',
                  onTap: () {
                    gameProvider.setCompturMode(value: true);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const GameTimeScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 15),
                _buildMenuButton(
                  'PLAYER vs FRIENDS ',
                  onTap: () {
                    gameProvider.setFriendsMode(value: true);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FriendListScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(String text, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(bottom: 10),
        width: 300,
        height: 80,
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage('assets/wooden_button.png'),
            fit: BoxFit.fill,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              shadows: [
                Shadow(
                  blurRadius: 2.0,
                  color: Colors.black,
                  offset: Offset(1.0, 1.0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
