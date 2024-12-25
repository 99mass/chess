import 'dart:async';

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
  late GameProvider _gameProvider;
  bool _isConnecting = false;
  int _connectionAttempts = 0;
  static const int _maxConnectionAttempts = 10;
  static const Duration _connectionDelay = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();

    // Initialiser le service WebSocket
    _webSocketService = WebSocketService();

    // Forcer la connexion WebSocket
    _forceWebSocketConnection();

    _gameProvider = Provider.of<GameProvider>(context, listen: false);

    // Charger l'utilisateur
    _gameProvider.loadUser();

    // Réinitialiser l'état de sortie de jeu si nécessaire
    if (_gameProvider.exitGame) {
      _gameProvider.setExitGame(value: false);
    }

    _gameProvider.setCompturMode(value: false);
    _gameProvider.setFriendsMode(value: false);
    _gameProvider.setGameModel();
    _gameProvider.setCurrentInvitation();

    // Gérer les invitations
    _gameProvider.invitationsStream.listen((invitations) {
      if (invitations.isNotEmpty) {
        final latestInvitation = invitations.last;
        _webSocketService.handleInvitationInteraction(
            context, _gameProvider.user, latestInvitation);
      }
    }, onError: (error) {
      print('Erreur dans le flux d\'invitations : $error');
      _forceWebSocketConnection();
    });

    // Gérer les utilisateurs en ligne
    _gameProvider.onlineUsersStream.listen((users) {});
  }

  void _forceWebSocketConnection() async {
    // Empêcher les tentatives de connexion simultanées
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    while (_connectionAttempts < _maxConnectionAttempts) {
      try {
        // print(
        //     'Tentative de connexion WebSocket (Tentative ${_connectionAttempts + 1})');

        await _webSocketService.connectWebSocket(context);

        // Si la connexion est réussie
        if (_webSocketService.isConnected) {
          setState(() {
            _isConnecting = false;
            _connectionAttempts = 0;
          });
          return;
        }

        // Incrémenter les tentatives et attendre avant la prochaine
        _connectionAttempts++;
        await Future.delayed(_connectionDelay);
      } catch (e) {
        print('Échec de la tentative de connexion : $e');
        _connectionAttempts++;
        await Future.delayed(_connectionDelay);
      }
    }

    // Si toutes les tentatives de connexion échouent
    if (mounted) {
      setState(() {
        _isConnecting = false;
      });
      _showFinalConnectionFailureDialog();
    }
  }

  void _showFinalConnectionFailureDialog() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Connection Error'),
            content: const Text(
                'Unable to connect to the server. Please check your internet connection and try again.'),
            actions: [
              TextButton(
                child: const Text('Retry'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _connectionAttempts = 0;
                  _forceWebSocketConnection();
                },
              ),
              TextButton(
                child: const Text('Close'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void dispose() {
    _gameProvider.clearInvitations();
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
            // Show connection status
            if (_isConnecting)
              Column(
                children: [
                  const CircularProgressIndicator(
                    color: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Connecting... (Attempt ${_connectionAttempts + 1})',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),

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
                  onTap: _webSocketService.isConnected
                      ? () {
                          gameProvider.setCompturMode(value: true);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const GameTimeScreen(),
                            ),
                          );
                        }
                      : null,
                ),
                const SizedBox(height: 15),
                _buildMenuButton(
                  'PLAYER vs FRIENDS ',
                  onTap: _webSocketService.isConnected
                      ? () {
                          gameProvider.setFriendsMode(value: true);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FriendListScreen(),
                            ),
                          );
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap != null ? 1.0 : 0.5,
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
              style: TextStyle(
                color: onTap != null ? Colors.white : Colors.grey,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                shadows: const [
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
      ),
    );
  }
}
