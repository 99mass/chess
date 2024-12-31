import 'dart:async';
import 'dart:convert';

import 'package:chess/constant/constants.dart';
import 'package:chess/screens/friend_list_screen.dart';
import 'package:chess/screens/login_screen.dart';
import 'package:chess/screens/waiting_room_screen.dart';
import 'package:chess/services/user_service.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:chess/widgets/custom_alert_dialog.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
import 'package:chess/widgets/custom_snack_bar.dart';
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
  bool _isInitializing = false;
  Timer? _reconnectTimer;
  StreamSubscription? _invitationsSubscription;
  StreamSubscription? _onlineUsersSubscription;

  @override
  void initState() {
    super.initState();

    // Initialize websocket service
    _webSocketService = WebSocketService();
    _gameProvider = Provider.of<GameProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
    });
  }

  Future<void> _initializeServices() async {
    setState(() => _isInitializing = true);

    try {
      // Initialize game state
      _initializeGameState();

      // Initialize WebSocket
      bool connected = await _webSocketService.initializeConnection(context);
      if (!connected) {
        if (mounted) {
          showCustomSnackBarTop(context,
              "Connexion au serveur impossible. Certaines fonctionnalités peuvent être indisponibles.");
        }
      }

      // Setup subscriptions
      _setupSubscriptions();
    } catch (e) {
      print('Error during initialization: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _initializeGameState() {
    _gameProvider.loadUser();

    if (_gameProvider.exitGame) {
      _gameProvider.setExitGame(value: false);
    }
    _gameProvider.setCompturMode(value: false);
    _gameProvider.setFriendsMode(value: false);
    _gameProvider.setOnlineMode(value: false);
    _gameProvider.setInvitationRejct(value: false);
    _gameProvider.setCancelWaintingRoom(value: false);
    _gameProvider.setInvitationTimeOut(value: false);
    _gameProvider.setGameModel();
    _gameProvider.setOnWillPop(value: false);
    _gameProvider.setCurrentInvitation();
  }

  void _setupSubscriptions() {
    // Cancel existing subscriptions if any
    _invitationsSubscription?.cancel();
    _onlineUsersSubscription?.cancel();

    // Setup new subscriptions
    _onlineUsersSubscription =
        _gameProvider.onlineUsersStream.listen((users) {}, onError: (error) {
      print('Error in online users stream: $error');
    });

    _invitationsSubscription =
        _gameProvider.invitationsStream.listen((invitations) {
      if (invitations.isNotEmpty) {
        final latestInvitation = invitations.last;
        _webSocketService.handleInvitationInteraction(
            context, _gameProvider.user, latestInvitation);
      }
    }, onError: (error) {
      print('Error in invitations stream: $error');
    });
  }

  void _handleComputerModeClick() {
    _gameProvider.setCompturMode(value: true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GameTimeScreen(),
      ),
    );
  }

  void _handleFriendsModeClick() async {
    if (!_webSocketService.isConnected) {
      // Tentative de reconnexion avant d'accéder aux fonctionnalités en ligne
      bool connected = await _webSocketService.initializeConnection(context);
      if (!connected) {
        if (mounted) {
          showCustomSnackBarTop(context,
              "Connexion impossible. Veuillez vérifier votre connexion internet.");
        }
        return;
      }
    }
    _gameProvider.setInvitationCancel(value: false);
    _gameProvider.setFriendsMode(value: true);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FriendListScreen()),
      );
    }
  }

  void _handleOnlineModeClick() async {
    if (!_webSocketService.isConnected) {
      // Tentative de reconnexion avant d'accéder aux fonctionnalités en ligne
      bool connected = await _webSocketService.initializeConnection(context);
      if (!connected) {
        if (mounted) {
          showCustomSnackBarTop(context,
              "Connexion impossible. Veuillez vérifier votre connexion internet.");
        }
        return;
      }
    }

    _webSocketService.sendMessage(json.encode({'type': 'public_game_request'}));
    if (mounted) {
      _gameProvider.setOnlineMode(value: true);

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WaitingRoomScreen()),
      );
    }
  }

  Future<void> _logOut() async {
    final user = await SharedPreferencesStorage.instance.getUserLocally();

    try {
      bool response = await UserService.disconnectUser(user!.userName);

      if (response == true) {
        await SharedPreferencesStorage.instance.deleteUserLocally();
        showCustomSnackBarTop(context, "Vous avez été déconnect  avec succées");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
      } else {
        showCustomSnackBarTop(
            context, "Une erreur s'est produite, veuillez reessayer!");
      }
    } on AuthException catch (e) {
      print('Erreur lors de la déconnexion: ${e.message}');
      showCustomSnackBarTop(
          context, "Erreur lors de la déconnexion: ${e.message}");
    } catch (e) {
      print('Erreur inattendue: $e');
      showCustomSnackBarTop(context, "Erreur inattendue: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsConstants.colorBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: ColorsConstants.colorBg,
        leading: null,
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                barrierDismissible: true,
                builder: (context) => CustomAlertDialog(
                  titleMessage: "Avertissement!",
                  subtitleMessage:
                      "Etes-vous sur de vouloir quitter l'application?",
                  typeDialog: 3,
                  onOk: () => _logOut(),
                ),
              );
            },
            style: IconButton.styleFrom(
                padding: const EdgeInsets.only(top: 20.0, right: 20.0)),
            icon: Image.asset(
              'assets/icons8_logout.png',
              width: 30,
            ),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: ColorsConstants.colorBg,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_isInitializing)
              const Column(
                children: [
                  CustomImageSpinner(
                    size: 30.0,
                    duration: Duration(seconds: 2),
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
              margin: const EdgeInsets.only(top: 50),
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
                  'Jouer en ligne',
                  'icons8_online.png',
                  onTap: _handleOnlineModeClick,
                ),
                const SizedBox(height: 15),
                _buildMenuButton(
                  'Jouer avec des amis',
                  'icons8_handshake.png',
                  onTap: _handleFriendsModeClick,
                ),
                const SizedBox(height: 15),
                _buildMenuButton(
                  'Jouer avec l\'ordinateur',
                  'icons8_ai.png',
                  onTap: _handleComputerModeClick,
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
            const SizedBox(width: 20),
            Image(
              image: AssetImage('assets/$imageAsset'),
              width: 70,
              height: 70,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(
                  color: ColorsConstants.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _invitationsSubscription?.cancel();
    _onlineUsersSubscription?.cancel();
    _reconnectTimer?.cancel();
    _gameProvider.clearInvitations();
    super.dispose();
  }
}
