import 'dart:async';

import 'package:chess/constant/constants.dart';
import 'package:chess/screens/friend_list_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:chess/widgets/custom_alert_dialog.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
import 'package:flutter/material.dart';
import 'package:chess/model/invitation_model.dart';
import 'package:provider/provider.dart';
import 'package:chess/provider/game_provider.dart';

class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({
    super.key,
  });

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late GameProvider _gameProvider;
  late WebSocketService _webSocketService;
  late InvitationMessage? invitation;

  @override
  void initState() {
    super.initState();
    // Initialize WebSocket connection
    _webSocketService = WebSocketService();
    _gameProvider = context.read<GameProvider>();

    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _gameProvider.loadUser();

    invitation = _gameProvider.currentInvitation;
  }

  Future<bool> _onWillPop() async {
    if (_gameProvider.invitationRejct) {
      _gameProvider.setInvitationRejct(value: false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const FriendListScreen(),
        ),
      );
      return true;
    }

    if (!_gameProvider.invitationRejct) {
      // Show confirmation dialog
      bool? shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => const CustomAlertDialog(
          titleMessage: "Annuler l'invitation ?",
          subtitleMessage:
              "Êtes-vous sûr de vouloir quitter la salle d'attente ?",
          typeDialog: 1,
        ),
      );

      if (shouldExit == true) {
        alertOtherPlayer();
      }
      return shouldExit ?? false;
    }

    return false;
  }

  void alertOtherPlayer() async {
    if (invitation != null) {
      _webSocketService.sendInvitationCancel(invitation!);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const FriendListScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: ColorsConstants.colorBg,
        appBar: AppBar(
          backgroundColor: ColorsConstants.colorBg,
          leading: IconButton(
            icon: Image.asset(
              'assets/icons8_arrow_back.png',
              width: 30,
            ),
            onPressed: () {
              _onWillPop();
            },
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const CustomImageSpinner(
                size: 100.0,
                duration: Duration(milliseconds: 2000),
                type: false,
              ),
              const SizedBox(height: 20),
              Text(
                invitation != null
                    ? (invitation!.toUsername != gameProvider.user.userName
                        ? 'En attente de ${invitation!.toUsername}'
                        : 'En attente de ${invitation!.fromUsername}')
                    : 'Aucune invitation disponible',
                style: const TextStyle(
                  fontSize: 25,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
