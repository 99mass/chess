import 'dart:async';

import 'package:chess/constant/constants.dart';
import 'package:chess/model/friend_model.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/game_time_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
import 'package:chess/widgets/custom_snack_bar.dart';
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
  bool _isInitializing = false;

   StreamSubscription? _onlineUsersSubscription;
   StreamSubscription? _invitationsSubscription;

  @override
  void initState() {
    super.initState();
    _webSocketService = WebSocketService();
    _gameProvider = Provider.of<GameProvider>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScreen();
    });
  }

  Future<void> _initializeScreen() async {
    setState(() => _isInitializing = true);

    try {
      bool connected = await _webSocketService.initializeConnection(context);
      if (!connected && mounted) {
        Navigator.pop(context);
        showCustomSnackBarTop(context,
            "Impossible de se connecter au serveur. Veuillez réessayer plus tard.");
        return;
      }

      _setupSubscriptions();
    } catch (e) {
      print('Error initializing FriendListScreen: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _setupSubscriptions() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsConstants.colorBg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: ColorsConstants.colorBg,
        leading: IconButton(
          icon: Image.asset(
            'assets/icons8_arrow_back.png',
            width: 30,
          ),
          onPressed: () async {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _isInitializing
          ? const Center(
              child: CustomImageSpinner(
                size: 30.0,
                duration: Duration(milliseconds: 2000),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(bottom: 20.0),
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage('assets/chess_logo.png'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<UserProfile>>(
                    stream: _gameProvider.onlineUsersStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CustomImageSpinner(
                            size: 30.0,
                            duration: Duration(milliseconds: 2000),
                          ),
                        );
                      }

                      onlineUsers = [];
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return _buildEmptyMessage();
                      }

                      for (var user in snapshot.data!) {
                        if (_gameProvider.user.id != user.id) {
                          if (!user.isInRoom) {
                            onlineUsers.add(user);
                          }
                        }
                      }

                      if (onlineUsers.isEmpty) {
                        return _buildEmptyMessage();
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: onlineUsers.length,
                        itemBuilder: (context, index) {
                          return _buildFriendItem(context, onlineUsers[index]);
                        },
                      );
                    },
                  ),
                ),
              ],
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const WaitingRoomScreen(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              ColorsConstants.colorBg,
              ColorsConstants.colorGreen,
              ColorsConstants.colorBg2,
              ColorsConstants.colorBg2,
              ColorsConstants.colorGreen,
              ColorsConstants.colorBg2,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: ColorsConstants.colorBg3, width: 1),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Image(
                  image: AssetImage('assets/avatar.png'),
                  width: 60,
                  height: 60,
                ),
                const SizedBox(width: 10),
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
            const Icon(
              Icons.chevron_right,
              color: Colors.white,
              size: 30,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyMessage() {
    return Padding(
      padding: const EdgeInsets.only(top: 50.0, left: 20.0, right: 20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Image(
            image: AssetImage('assets/icons8_empty.png'),
            width: 100,
            height: 100,
          ),
          const Text(
            'Aucun utilisateur en ligne pour le moment.\nEn attendant, amusez-vous à jouer contre notre IA en cliquant sur le bouton ci-dessous !',
            style: TextStyle(color: ColorsConstants.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ColorsConstants.colorBg2,
              foregroundColor: ColorsConstants.white,
              minimumSize: const Size(150, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 5,
            ),
            child: const Text(
              'Jouer en solo',
              style: TextStyle(
                color: ColorsConstants.white,
                fontSize: 20,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GameTimeScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _onlineUsersSubscription?.cancel();
    _invitationsSubscription?.cancel();
    _gameProvider.clearInvitations();
    super.dispose();
  }
}
