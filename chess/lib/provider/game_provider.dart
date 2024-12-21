// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';

import 'package:bishop/bishop.dart' as bishop;
import 'package:chess/constant/constants.dart';
import 'package:chess/model/friend_model.dart';
import 'package:chess/model/game_model.dart';
import 'package:chess/model/invitation_model.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _computerMode = value;
      notifyListeners();
    });
  }

  void setFriendsMode({required bool value}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _friendsMode = value;
      notifyListeners();
    });
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

  String _gameId = '';
  String _opponentUsername = '';
  bool _exitGame = false;
  bool _isWhiterPlayer = false;
  bool _isMyTurn = false;
  bool _isOpponentTurn = false;
  int _lastWhiteTime = 0;
  int _lastBlackTime = 0;

  // Multiplayer game data
  GameModel? _gameModel;
  bool _isFlipBoard = false;
  bool get isWhitePlayer => _isWhiterPlayer;
  bool get isMyTurn => _isMyTurn;
  bool get isOpponentTurn => _isOpponentTurn;
  int get lastWhiteTime => _lastWhiteTime;
  int get lastBlackTime => _lastBlackTime;

  // Existing getters...
  GameModel? get gameModel => _gameModel;
  String get gameId => _gameId;
  String get opponentUsername => _opponentUsername;
  bool get isFlipBoard => _isFlipBoard;
  bool get exitGame => _exitGame;

  void setGameModel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameModel = null;
      notifyListeners();
    });
  }

  void setIsMyTurn({required bool value}) {
    _isMyTurn = value;
    notifyListeners();
  }

  void setIsOpponentTurn({required bool value}) {
    _isOpponentTurn = value;
    notifyListeners();
  }

  void setLastWhiteTime({required int value}) {
    _lastWhiteTime = value;
    notifyListeners();
  }

  void setLastBlackTime({required int value}) {
    _lastBlackTime = value;
    notifyListeners();
  }


  void setExitGame({required bool value}) {
    _exitGame = value;
    Future.microtask(() {
      notifyListeners();
    });
  }

  void setIsFlipBoard({required bool value}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isFlipBoard = value;
      notifyListeners();
    });
  }

  void setOpponentUsername({required String username}) {
    _opponentUsername = username;
    notifyListeners();
  }

  // initialize a multiplayer game
  void initializeMultiplayerGame(Map<String, dynamic> gameData) {
    // Parse game data into GameModel
    _gameModel = GameModel.fromJson(gameData);
    _gameId = _gameModel!.gameId;

    // Determine player's perspective and board orientation
    bool isPlayerWhite = _userProfile.id == _gameModel!.gameCreatorUid;

    _isWhiterPlayer = isPlayerWhite;

    if (_gameModel!.gameCreatorUid == _userProfile.id) {
      _isWhiterPlayer = !isPlayerWhite;
      _isMyTurn = true;
      _isOpponentTurn = false;
    } else {
      _isMyTurn = false;
      _isOpponentTurn = true;
    }

    // Set player's color and board orientation
    _player = isPlayerWhite ? Squares.white : Squares.black;
    _playerColor = isPlayerWhite ? PlayerColor.white : PlayerColor.black;

    // Initialize game with FEN position
    _game = bishop.Game(
        variant: bishop.Variant.standard(), fen: _gameModel!.positonFen);

    // Adjust the game state based on player's perspective
    _state = _game.squaresState(_player);

    // Set game mode
    _computerMode = false;
    _friendsMode = true;

    // Set player IDs
    _whitePlayerId = int.tryParse(_gameModel!.gameCreatorUid) ?? -1;
    _blackPlayerId = int.tryParse(_gameModel!.userId) ?? -1;

    // Determine current player based on turn and player's perspective
    _currentPlayerId = _gameModel!.isWhitesTurn
        ? (isPlayerWhite ? _whitePlayerId : _blackPlayerId)
        : (isPlayerWhite ? _blackPlayerId : _whitePlayerId);

    // Set game time if available
    _gameTime = int.tryParse(_gameModel!.whitesTime) ?? 0;

    // Set game end status
    _isGameEnd = _gameModel!.isGameOver;

    notifyListeners();
  }

  void handleOpponentMove(Map<String, dynamic> moveData) {
    // Vérifier si ce n'est pas notre propre mouvement
    if (moveData['fromUserId'] == user.id) {
      return;
    }

    // Determine player's perspective and board orientation
    bool isPlayerWhite = _userProfile.id == _gameModel!.gameCreatorUid;

    _isWhiterPlayer = isPlayerWhite;

    if (_gameModel!.gameCreatorUid == _userProfile.id) {
      _isWhiterPlayer = !isPlayerWhite;
    }

    try {
      // Mettre à jour l'état du jeu avec la nouvelle position FEN
      _game =
          bishop.Game(variant: bishop.Variant.standard(), fen: moveData['fen']);

      _state = _game.squaresState(_player);
      _gameModel?.isWhitesTurn = moveData['isWhitesTurn'];
      notifyListeners();
    } catch (e) {
      print('Error handling opponent move: $e');
    }
  }

  

  List<UserProfile> _onlineUsers = [];
  // ignore: prefer_final_fields
  List<InvitationMessage> _invitations = [];
  InvitationMessage? _currentInvitation;

  // Streams for online users and invitations
  final StreamController<List<UserProfile>> _onlineUsersController =
      StreamController<List<UserProfile>>.broadcast();
  final StreamController<List<InvitationMessage>> _invitationsController =
      StreamController<List<InvitationMessage>>.broadcast();

  List<UserProfile> get onlineUsers => _onlineUsers;

  Stream<List<UserProfile>> get onlineUsersStream =>
      _onlineUsersController.stream;
  Stream<List<InvitationMessage>> get invitationsStream =>
      _invitationsController.stream;
  InvitationMessage? get currentInvitation => _currentInvitation;

  // Method to update online users
  void updateOnlineUsers(List<UserProfile> users) {
    _onlineUsers = users.toSet().toList();
    _onlineUsersController.add(_onlineUsers);
    notifyListeners();
  }

  // Method to add a new invitation
  void addInvitation(InvitationMessage invitation) {
    // Prevent duplicate invitations
    if (!_invitations.any((inv) =>
        inv.fromUserId == invitation.fromUserId &&
        inv.toUserId == invitation.toUserId)) {
      _invitations.add(invitation);
      _invitationsController.add(_invitations);
      notifyListeners();
    }
  }

  // Method to remove an invitation
  void removeInvitation(InvitationMessage invitation) {
    _invitations.removeWhere((inv) =>
        inv.fromUserId == invitation.fromUserId &&
        inv.toUserId == invitation.toUserId);
    _invitationsController.add(_invitations);
    notifyListeners();
  }

  // Method to clear all invitations
  void clearInvitations() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _invitations.clear();
      _invitationsController.add(_invitations);
      notifyListeners();
    });
  }

  void createInvitation({
    required UserProfile toUser,
    required UserProfile fromUser,
  }) {
    _currentInvitation = InvitationMessage(
      type: 'invitation_send',
      fromUserId: fromUser.id,
      fromUsername: fromUser.userName,
      toUserId: toUser.id,
      toUsername: toUser.userName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    setOpponentUsername(username: toUser.userName);

    notifyListeners();
  }

  void clearCurrentInvitation() {
    _currentInvitation = null;
    notifyListeners();
  }

  void setCurrentInvitation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentInvitation = null;
      notifyListeners();
    });
  }

  void updateCurrentInvitation(InvitationMessage invitation) {
    _currentInvitation = invitation;
    notifyListeners();
  }

  // Method to handle invitation rejection
  void handleInvitationRejection(
      BuildContext context, InvitationMessage invitation) {
    removeInvitation(invitation);
    // Additional logic for handling rejection can be added here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invitation.fromUsername} rejected your invitation'),
        duration: const Duration(seconds: 5),
      ),
    );
    Timer(const Duration(seconds: 2), () {});
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const MainMenuScreen(),
        ));
  }

  // Method to handle invitation cancellation
  void handleInvitationCancellation(
      BuildContext context, InvitationMessage invitation) {
    removeInvitation(invitation);
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invitation.toUsername} canceled the invitation'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void handleInvitationAccepted(
      BuildContext context, InvitationMessage invitation) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invitation.fromUsername} accepted your invitation'),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // Dispose method to close streams
  @override
  void dispose() {
    _onlineUsersController.close();
    _invitationsController.close();
    super.dispose();
  }
}
