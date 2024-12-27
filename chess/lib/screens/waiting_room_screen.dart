import 'dart:async';

import 'package:chess/constant/constants.dart';
import 'package:chess/screens/main_menu_screen.dart';
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
  late WebSocketService _webSocketService;
  late InvitationMessage? invitation;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    _cancelTimer();
    // Initialize animation controller
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    // Get the InvitationService from GameProvider
    final gameProvider = context.read<GameProvider>();
    gameProvider.loadUser();

    invitation = gameProvider.currentInvitation;

    // Initialize WebSocket connection
    _webSocketService = WebSocketService();
    _webSocketService.connectWebSocket(context);

    // Start timeout timer
    _timeoutTimer = Timer(const Duration(seconds: 30), _handleTimeout);
  }

  void _handleTimeout() {
    if (mounted) {
      _cancelTimer();

      final gameProvider = context.read<GameProvider>();
      if (invitation != null && gameProvider.gameModel == null) {
        // Cancel invitation
        _webSocketService.sendInvitationCancel(invitation!);
      }

      if (gameProvider.gameModel == null && !gameProvider.invitationCancel) {
        // Show timeout message and navigate to main menu
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => CustomAlertDialog(
            titleMessage: "Demande expirée !",
            subtitleMessage:
                "La demande d'invitation a expirée. Veuillez réessayer.",
            typeDialog: 0,
            onOk: () {
              _cancelTimer();
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const MainMenuScreen(),
                ),
              );
            },
          ),
        );
      }
    }
  }

  void _cancelTimer() {
    if (_timeoutTimer != null) {
      _timeoutTimer!.cancel();
      _timeoutTimer = null;
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    _controller.dispose();
    _webSocketService.disposeInvitationStream();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    _cancelTimer();

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

  void alertOtherPlayer() async {
    if (invitation != null) {
      _webSocketService.sendInvitationCancel(invitation!);
    }
    _cancelTimer();

    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const MainMenuScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();
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
}
