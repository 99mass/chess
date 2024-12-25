import 'dart:async';

import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
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
          builder: (context) => AlertDialog(
            title: const Text('Request Timeout'),
            content: const Text(
                'The invitation request has timed out. Please try again.'),
            actions: [
              TextButton(
                child: const Text('OK'),
                onPressed: () {
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
            ],
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
      builder: (context) => AlertDialog(
        title: const Text('Cancel Game Invitation'),
        content: const Text('Are you sure you want to leave the waiting room?'),
        actions: [
          TextButton(
            child: const Text('No'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('Yes'),
            onPressed: () {
              if (invitation != null) {
                _webSocketService.sendInvitationCancel(invitation!);
              }

              _cancelTimer();

              _timeoutTimer?.cancel(); // Cancel the timeout timer
              _timeoutTimer = null;

              Timer(const Duration(seconds: 1), () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MainMenuScreen(),
                  ),
                );
              });
            },
          ),
        ],
      ),
    );

    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black54,
        appBar: AppBar(
          title: const Text(
            'Chess Waiting Room',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          backgroundColor: Colors.amber[700],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _onWillPop();
            },
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                invitation != null
                    ? (invitation!.toUsername != gameProvider.user.userName
                        ? 'Waiting for ${invitation!.toUsername}'
                        : 'Waiting for ${invitation!.fromUsername}')
                    : 'No invitation available',
                style: const TextStyle(
                  fontSize: 25,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 40),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.scale(
                    scale:
                        1.0 + 0.3 * math.sin(_controller.value * 2 * math.pi),
                    child: child,
                  );
                },
                child: Icon(
                  Icons.local_florist_rounded,
                  size: 80,
                  color: Colors.amber[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
