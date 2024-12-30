import 'package:chess/provider/time_provider.dart';
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


