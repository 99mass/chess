import 'package:chess/provider/time_provider.dart';
import 'package:flutter/material.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:squares/squares.dart';

// String getTimerToDisplay({
//   required GameProvider gameProvider,
//   required ChessTimer chessTimer,
//   required bool isUser,
// }) {
//   // Pour le mode multijoueur (user vs user)
//   if (gameProvider.friendsMode) {
//     // Si c'est le joueur du bas (isUser = true)
//     if (isUser) {
//       // Si le joueur du bas joue les blancs
//       if (gameProvider.isWhitePlayer) {
//         return chessTimer.formatTime(chessTimer.whiteRemainingTime);
//       } else {
//         // Si le joueur du bas joue les noirs
//         return chessTimer.formatTime(chessTimer.blackRemainingTime);
//       }
//     } else {
//       // Pour le joueur du haut (isUser = false)
//       // Si le joueur du bas joue les blancs, le haut joue les noirs
//       if (gameProvider.isWhitePlayer) {
//         return chessTimer.formatTime(chessTimer.blackRemainingTime);
//       } else {
//         // Si le joueur du bas joue les noirs, le haut joue les blancs
//         return chessTimer.formatTime(chessTimer.whiteRemainingTime);
//       }
//     }
//   }

//   // Pour le mode ordinateur ou autre
//   if (isUser) {
//     if (gameProvider.player == Squares.white) {
//       return chessTimer.formatTime(chessTimer.whiteRemainingTime);
//     } else {
//       return chessTimer.formatTime(chessTimer.blackRemainingTime);
//     }
//   } else {
//     if (gameProvider.player == Squares.white) {
//       return chessTimer.formatTime(chessTimer.blackRemainingTime);
//     } else {
//       return chessTimer.formatTime(chessTimer.whiteRemainingTime);
//     }
//   }
// }
String getTimerToDisplay({
  required GameProvider gameProvider,
  required ChessTimer chessTimer,
  required bool isUser,
}) {
  String timer = '';
  // check if is user
  
  if (isUser) {
    if (gameProvider.player == Squares.white) {
      timer = chessTimer.formatTime(chessTimer.whiteRemainingTime);
    }
    if (gameProvider.player == Squares.black) {
      timer = chessTimer.formatTime(chessTimer.blackRemainingTime);
    }
  } else {
    // if its not user do the opposite
    if (gameProvider.player == Squares.white) {
      timer = chessTimer.formatTime(chessTimer.blackRemainingTime);
    }
    if (gameProvider.player == Squares.black) {
      timer = chessTimer.formatTime(chessTimer.whiteRemainingTime);
    }
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
