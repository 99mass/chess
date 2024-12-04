import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/game_time_screen.dart';
import 'package:chess/screens/waiting_room_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();

    return Scaffold(
      backgroundColor: Colors.black54,
      appBar: AppBar(
        title: const Text(
          'Chess Mode',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.amber[700],
        automaticallyImplyLeading: false,
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildMenuButton(
              text: 'Play Online',
              icon: Icons.public,
              onPressed: () {
                gameProvider.setOnLineMode(value: true);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WaitingRoomScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildMenuButton(
              text: 'Play vs Computer',
              icon: Icons.computer,
              onPressed: () {
                gameProvider.setCompturMode(value: true);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GameTimeScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildMenuButton(
              text: 'Friend Invitation',
              icon: Icons.people,
              onPressed: () {
                gameProvider.setFriendMode(value: true);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WaitingRoomScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: Colors.black87),
      label: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber[600],
        foregroundColor: Colors.black87,
        minimumSize: const Size(250, 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        elevation: 5,
      ),
    );
  }
}
