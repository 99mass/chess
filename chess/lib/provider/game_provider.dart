// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';

import 'package:bishop/bishop.dart' as bishop;
import 'package:chess/constant/constants.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/helper.dart';
import 'package:flutter/material.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:squares/squares.dart';

class GameProvider extends ChangeNotifier {
  late bishop.Game _game = bishop.Game(variant: bishop.Variant.standard());
  late SquaresState _state = _game.squaresState(0);
  bool _aiThinking = false;
  bool _flipBoard = false;
  bool _computerMode = false;
  bool _onLineMode = false;
  bool _friendrMode = false;
  bool _isLoading = false;

  int _player = Squares.white;
  PlayerColor _playerColor = PlayerColor.white;
  GameDifficulty _gameDifficulty = GameDifficulty.easy;
  int _gameTime = 0;
  late int _whitePlayerId;
  late int _blackPlayerId;
  int _currentPlayerId = -1;

  // getters
  bishop.Game get game => _game;
  SquaresState get state => _state;
  bool get aiThinking => _aiThinking;
  bool get flipBoard => _flipBoard;
  bool get computerMode => _computerMode;
  bool get onLineMode => _onLineMode;
  bool get friendMode => _friendrMode;
  bool get isloading => _isLoading;
  int get player => _player;
  PlayerColor get playerColor => _playerColor;
  GameDifficulty get gameDifficulty => _gameDifficulty;
  int get gameTime => _gameTime;
  int get whitePlayerId => _whitePlayerId;
  int get blackPlayerId => _blackPlayerId;
  int get currentPlayerId => _currentPlayerId;

  // setters
  getPositionFen() {
    return game.fen;
  }

  void resetGame({bool newGame = false}) {
    if (newGame) {
      if (_player == Squares.white) {
        _player = Squares.black;
      } else {
        _player = Squares.white;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _game = bishop.Game(variant: bishop.Variant.standard());
      _state = _game.squaresState(_player);
      notifyListeners();
    });
  }

  bool makeStringMove(String bestMove) {
    bool result = game.makeMoveString(bestMove);
    notifyListeners();
    return result;
  }

  Future<bool> makeSquaresMove(Move move,
      {required BuildContext context}) async {
    bool result = game.makeSquaresMove(move);

    print(
        'Game state: gameOver=${game.gameOver}, drawn=${game.drawn}, winner=${game.winner}');
    print('Game result: ${game.eliminated}');
    // Modification importante
    if (isStalemate()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialogGameOver(context, 'Stalemate! The game is a draw.',
            score: '1/2 - 1/2', onClose: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainMenuScreen()),
          );
        });
      });
    } else if (game.drawn || game.gameOver) {
      print('DRAW CONDITION DETECTED!');

      String message = 'Game Over!';
      String? score;

      if (game.drawn) {
        print('DRAW SPECIFICS');
        if (game.result == 'DrawnGameStalemate') {
          message = 'Stalemate! The game is a draw.';
          score = '1/2 - 1/2';
        } else if (game.result == '1/2-1/2') {
          message = 'Draw by agreement or insufficient material!';
          score = '1/2 - 1/2';
        } else {
          message = 'The game is a draw!';
          score = '1/2 - 1/2';
        }
      } else if (game.winner == Squares.white) {
        message = 'White wins!';
        score = '1 - 0';
      } else if (game.winner == Squares.black) {
        message = 'Black wins!';
        score = '0 - 1';
      }

      // Utilisation d'une m thode statique pour le dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          showDialogGameOver(context, message, score: score, onClose: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainMenuScreen()),
            );
          });
        } catch (e) {
          print('Erreur lors de l\'affichage du dialog: $e');
        }
      });
    }

    notifyListeners();
    return result;
  }

  bool isStalemate() {
    // Check if the current player has no possible moves
    return _state.moves.isEmpty && !_game.gameOver;
  }

  Future<void> setSquareState() async {
    _state = game.squaresState(player);
    notifyListeners();
  }

  void makeRandomMove() {
    _game.makeRandomMove();
    notifyListeners();
  }

  void flipTheBoard() {
    _flipBoard = !_flipBoard;
    notifyListeners();
  }

  void setAiThinking(bool value) {
    _aiThinking = value;
    notifyListeners();
  }

  void setCompturMode({required bool value}) {
    _computerMode = value;
    notifyListeners();
  }

  void setOnLineMode({required bool value}) {
    _onLineMode = value;
    notifyListeners();
  }

  void setFriendMode({required bool value}) {
    _friendrMode = value;
    notifyListeners();
  }

  void setIsloadind({required bool value}) {
    _isLoading = value;
    notifyListeners();
  }

  void setPlayerColor({required int player}) {
    _player = player;
    _playerColor =
        player == Squares.white ? PlayerColor.white : PlayerColor.black;
    notifyListeners();
  }

  void setGameDifficulty({required GameDifficulty gameDifficulty}) {
    _gameDifficulty = gameDifficulty;
    notifyListeners();
  }

  void setGameTime({required int gameTime}) {
    _gameTime = gameTime;
    notifyListeners();
  }

  void setWhitePlayerId({required int playerId}) {
    _whitePlayerId = playerId;
    notifyListeners();
  }

  void setBlackPlayerId({required int playerId}) {
    _blackPlayerId = playerId;
    notifyListeners();
  }

  void setCurrentPlayerId({required int playerId}) {
    _currentPlayerId = playerId;
    notifyListeners();
  }
}

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
    showDialogGameOver(
        context, _whiteRemainingTime == 0 ? 'Black wins!' : 'White wins!',
        onClose: () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainMenuScreen()),
      );
    });
    _activeTimer?.cancel();
    onTimeExpired?.call();
  }

  void dispose() {
    _activeTimer?.cancel();
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

// Extension method to integrate with existing GameProvider
extension ChessTimerExtension on GameProvider {
  void initializeTimer(BuildContext context, {VoidCallback? onTimeExpired}) {
    final chessTimer = ChessTimer(
        initialMinutes: gameTime,
        onTimeExpired: () {
          // Handle game end due to time
          onTimeExpired?.call();
        });

    // Start timer
    chessTimer.start(context: context, playerColor: playerColor);
  }
}
