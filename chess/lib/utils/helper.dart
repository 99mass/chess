import 'package:chess/provider/time_provider.dart';
import 'package:flutter/material.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:squares/squares.dart';

String getTimerToDisplay({
  required GameProvider gameProvider,
  required ChessTimer chessTimer,
  required bool isUser,
}) {
  String timer = '';

  if (gameProvider.friendsMode) {
    timer = isUser
        ? gameProvider.player == Squares.white
            ? chessTimer.formatTime(gameProvider.lastWhiteTime)
            : chessTimer.formatTime(gameProvider.lastBlackTime)
        : gameProvider.player == Squares.black
            ? chessTimer.formatTime(gameProvider.lastWhiteTime)
            : chessTimer.formatTime(gameProvider.lastBlackTime);
  } else {
    timer = isUser
        ? gameProvider.player == Squares.white
            ? chessTimer.formatTime(chessTimer.whiteRemainingTime)
            : chessTimer.formatTime(chessTimer.blackRemainingTime)
        : gameProvider.player == Squares.black
            ? chessTimer.formatTime(chessTimer.whiteRemainingTime)
            : chessTimer.formatTime(chessTimer.blackRemainingTime);
  }

  return timer;
}

void showDialogGameOver(BuildContext context, String message,
    {String? score, VoidCallback? onClose}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Colors.amber[700],
        title: const Text('Game Over', style: TextStyle(fontSize: 25)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                style: const TextStyle(fontSize: 20, color: Colors.white)),
            if (score != null) ...[
              const SizedBox(height: 10),
              Text(
                'Score: $score',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            child: const Text('OK',
                style: TextStyle(fontSize: 20, color: Colors.white)),
            onPressed: () {
              onClose?.call();
            },
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    },
  );
}
