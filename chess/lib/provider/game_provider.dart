// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';

import 'package:bishop/bishop.dart' as bishop;
import 'package:chess/constant/constants.dart';
import 'package:chess/model/friend_model.dart';
import 'package:chess/model/game_model.dart';
import 'package:chess/provider/time_provider.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/helper.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:flutter/material.dart';
import 'package:square_bishop/square_bishop.dart';
import 'package:squares/squares.dart';

class GameProvider extends ChangeNotifier {
  late bishop.Game _game = bishop.Game(variant: bishop.Variant.standard());
  late SquaresState _state = _game.squaresState(0);
  bool _aiThinking = false;
  bool _flipBoard = false;
  bool _computerMode = false;
  bool _friendsMode = false;
  bool _isLoading = false;
  bool _isGameEnd = false;

  int _player = Squares.white;
  PlayerColor _playerColor = PlayerColor.white;
  GameDifficulty _gameDifficulty = GameDifficulty.easy;
  int _gameTime = 0;
  late int _whitePlayerId;
  late int _blackPlayerId;
  int _currentPlayerId = -1;

  // user
  late UserProfile _userProfile = UserProfile(id: '', userName: '');

  // getters
  bishop.Game get game => _game;
  SquaresState get state => _state;
  bool get aiThinking => _aiThinking;
  bool get flipBoard => _flipBoard;
  bool get computerMode => _computerMode;
  bool get friendsMode => _friendsMode;
  bool get isloading => _isLoading;
  bool get isGameEnd => _isGameEnd;
  int get player => _player;
  PlayerColor get playerColor => _playerColor;
  GameDifficulty get gameDifficulty => _gameDifficulty;
  int get gameTime => _gameTime;
  int get whitePlayerId => _whitePlayerId;
  int get blackPlayerId => _blackPlayerId;
  int get currentPlayerId => _currentPlayerId;
  // user
  UserProfile get user => _userProfile;

  Future<void> loadUser() async {
    _userProfile = await SharedPreferencesStorage.instance.getUserLocally() ??
        UserProfile(id: '', userName: '');
    notifyListeners();
  }

  // setters
  // user
  void setUser(UserProfile user) async {
    _userProfile = user;
    await SharedPreferencesStorage.instance.saveUserLocally(user);
    notifyListeners();
  }

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

  Future<bool> makeSquaresMove(Move move,
      {required BuildContext context, ChessTimer? chessTimer}) async {
    bool result = game.makeSquaresMove(move);

    handleGameOver(context, chessTimer: chessTimer);

    notifyListeners();
    return result;
  }

  Future<bool> makeStringMove(String bestMove,
      {required BuildContext context, ChessTimer? chessTimer}) async {
    bool result = game.makeMoveString(bestMove);

    handleGameOver(context, chessTimer: chessTimer);

    notifyListeners();
    return result;
  }

  void handleGameOver(BuildContext context, {ChessTimer? chessTimer}) {
    if (game.drawn || game.gameOver) {
      _isGameEnd = true;

      String message = 'Game Over!';
      String? score;

      if (game.drawn) {
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

  void setFriendsMode({required bool value}) {
    _friendsMode = value;
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

  void setIsGameEnd({required bool value}) {
    _isGameEnd = value;
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

  // ----------------Game With Friend ---------------- //
  String _gameId = '';
  String _opponentUsername = '';

  // Multiplayer game data
  GameModel? _gameModel;

  // Existing getters...
  GameModel? get gameModel => _gameModel;
  String get gameId => _gameId;
  String get opponentUsername => _opponentUsername;

  void setOpponentUsername({required String username}) {
    _opponentUsername = username;
    notifyListeners();
  }

  // Method to initialize a multiplayer game
  void initializeMultiplayerGame(Map<String, dynamic> gameData) {
    // Parse game data into GameModel
    _gameModel = GameModel.fromJson(gameData);
    _gameId = _gameModel!.gameId;

    // Determine player color based on game data
    _player = _gameModel!.isWhitesTurn ? Squares.white : Squares.black;
    _playerColor =
        _player == Squares.white ? PlayerColor.white : PlayerColor.black;

    // Initialize game with FEN position
    _game = bishop.Game(
        variant: bishop.Variant.standard(),
        fen: _gameModel!.positonFen // Use the FEN from the game model
        );
    _state = _game.squaresState(_player);

    // Set game mode
    _computerMode = false;
    _friendsMode = true;

    // Set player IDs
    _whitePlayerId = int.tryParse(_gameModel!.gameCreatorUid) ?? -1;
    _blackPlayerId = int.tryParse(_gameModel!.userId) ?? -1;
    _currentPlayerId =
        _gameModel!.isWhitesTurn ? _whitePlayerId : _blackPlayerId;

    // Set game time if available
    _gameTime = int.tryParse(_gameModel!.whitesTime) ?? 0;

    // Set game end status
    _isGameEnd = _gameModel!.isGameOver;

    notifyListeners();
  }

  // Method to update game state from move
  void updateGameState(String fen, bool isWhitesTurn) {
    _game = bishop.Game(variant: bishop.Variant.standard(), fen: fen);
    _state = _game.squaresState(_player);
    _player = isWhitesTurn ? Squares.white : Squares.black;
    _playerColor =
        _player == Squares.white ? PlayerColor.white : PlayerColor.black;

    notifyListeners();
  }

  void synchronizeMove(String move) {
    try {
      // Attempt to make the move
      bool result = _game.makeMoveString(move);

      if (result) {
        _state = _game.squaresState(_player);
        _isGameEnd = _game.gameOver;

        // Switch player
        _player = _player == Squares.white ? Squares.black : Squares.white;
        _playerColor =
            _player == Squares.white ? PlayerColor.white : PlayerColor.black;

        notifyListeners();
      }
    } catch (e) {
      print('Error synchronizing move: $e');
    }
  }
}
