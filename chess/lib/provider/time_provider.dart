// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';
import 'package:chess/constant/constants.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/utils/helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChessTimer {
  final int initialMinutes;
  int _whiteRemainingTime;
  int _blackRemainingTime;
  Timer? _activeTimer;
  bool _isWhiteTurn;
  final VoidCallback? onTimeExpired;
  final void Function()? onTimerUpdate;

  ChessTimer({
    required this.initialMinutes,
    this.onTimeExpired,
    this.onTimerUpdate,
    bool startWithWhite = true,
  })  : _whiteRemainingTime = initialMinutes * 60,
        _blackRemainingTime = initialMinutes * 60,
        _isWhiteTurn = startWithWhite;

  int get whiteRemainingTime => _whiteRemainingTime;
  int get blackRemainingTime => _blackRemainingTime;
  bool get isWhiteTurn => _isWhiteTurn;

  void start(
      {required BuildContext context, required PlayerColor playerColor}) {
    _activeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final gameProvider = Provider.of<GameProvider>(context, listen: false);

      if (gameProvider.friendsMode) {
        return;
      }

      if (_isWhiteTurn == (playerColor == PlayerColor.white)) {
        _whiteRemainingTime--;
        if (_whiteRemainingTime <= 0) {
          _handleTimeExpired(context);
        }
      } else {
        _blackRemainingTime--;
        if (_blackRemainingTime <= 0) {
          _handleTimeExpired(context);
        }
      }

      onTimerUpdate?.call();
    });
  }

  void switchTurn() {
    _isWhiteTurn = !_isWhiteTurn;
  }

  void _handleTimeExpired(BuildContext context) {
    final gameProvider = Provider.of<GameProvider>(context, listen: false);
    gameProvider.setIsGameEnd(value: true);
    gameProvider.setOnWillPop(value: true);
    gameProvider.setFriendsMode(value: false);
    gameProvider.setIsloading( false);
    showDialogGameOver(
        context, _whiteRemainingTime == 0 ? 'Black wins!' : 'White wins!',
        onClose: () {
      stop();
      dispose();
    });
    _activeTimer?.cancel();
    onTimeExpired?.call();
  }

  void stop() {
    _activeTimer?.cancel();
    onTimeExpired?.call();
    _activeTimer = null;
  }

  void dispose() {
    _activeTimer?.cancel();
    onTimeExpired?.call();
    _activeTimer = null;
  }

  String formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void reset() {
    _whiteRemainingTime = initialMinutes * 60;
    _blackRemainingTime = initialMinutes * 60;
  }
}
