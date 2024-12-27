import 'dart:async';

import 'package:chess/constant/constants.dart';
import 'package:chess/screens/friend_list_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:chess/widgets/custom_alert_dialog.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
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
        builder: (context) => const CustomAlertDialog(
          titleMessage: "Connection Error!",
          subtitleMessage:
              "Impossible de se connecter au serveur.\nVeuillez vérifier votre connexion internet et réessayer.",
            typeDialog: 0,
        ),
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
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: ColorsConstants.colorBg,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Show connection status
            if (_isConnecting)
              const Column(
                children: [
                  CustomImageSpinner(
                    size: 30.0,
                    duration: Duration(milliseconds: 2000),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Connexion en cours...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),

            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/chess_logo.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Nouvelle partie',
                  style: TextStyle(fontSize: 25, color: ColorsConstants.white),
                ),
                const SizedBox(height: 40),
                _buildMenuButton(
                  'vs Ordinateur',
                  'icons8_ai.png',
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
                  'vs Amis',
                  'icons8_handshake.png',
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

  Widget _buildMenuButton(String text, String imageAsset,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        width: 280,
        decoration: const BoxDecoration(
          color: ColorsConstants.colorBg2,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 40),
            Image(
              image: AssetImage('assets/$imageAsset'),
              width: 70,
              height: 70,
            ),
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(
                color: ColorsConstants.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
