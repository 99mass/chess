// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';
import 'dart:convert';

import 'package:bishop/bishop.dart' as bishop;
import 'package:chess/constant/constants.dart';
import 'package:chess/model/friend_model.dart';
import 'package:chess/model/game_model.dart';
import 'package:chess/model/invitation_model.dart';
import 'package:chess/provider/time_provider.dart';
import 'package:chess/screens/friend_list_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:chess/utils/custom_page_route.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:chess/widgets/custom_alert_dialog.dart';
import 'package:chess/widgets/custom_snack_bar.dart';
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
  bool _onlineMode = false;
  bool _isLoading = false;
  bool _isGameEnd = false;

  int _player = Squares.white;
  PlayerColor _playerColor = PlayerColor.white;
  GameDifficulty _gameDifficulty = GameDifficulty.easy;
  int _gameTime = 0;
  late UserProfile _userProfile = UserProfile(id: '', userName: '');
  String _gameId = '';
  String _opponentUsername = '';
  bool _exitGame = false;
  bool _isWhiterPlayer = false;
  bool _isMyTurn = false;
  bool _isOpponentTurn = false;
  int _lastWhiteTime = 0;
  int _lastBlackTime = 0;
  bool _onWillPop = false;
  bool _invitationCancel = false;

  // getters
  bishop.Game get game => _game;
  SquaresState get state => _state;
  bool get aiThinking => _aiThinking;
  bool get flipBoard => _flipBoard;
  bool get computerMode => _computerMode;
  bool get friendsMode => _friendsMode;
  bool get onlineMode => _onlineMode;
  bool get isloading => _isLoading;
  bool get isGameEnd => _isGameEnd;
  int get player => _player;
  PlayerColor get playerColor => _playerColor;
  GameDifficulty get gameDifficulty => _gameDifficulty;
  int get gameTime => _gameTime;
  UserProfile get user => _userProfile; // user

  GameModel? _gameModel;
  bool get isWhitePlayer => _isWhiterPlayer;
  bool get isMyTurn => _isMyTurn;
  bool get isOpponentTurn => _isOpponentTurn;
  int get lastWhiteTime => _lastWhiteTime;
  int get lastBlackTime => _lastBlackTime;
  GameModel? get gameModel => _gameModel;
  String get gameId => _gameId;
  String get opponentUsername => _opponentUsername;
  bool get exitGame => _exitGame;
  bool get onWillPop => _onWillPop;
  bool get invitationCancel => _invitationCancel;

  Future<void> loadUser() async {
    _userProfile = await SharedPreferencesStorage.instance.getUserLocally() ??
        UserProfile(id: '', userName: '');
    notifyListeners();
  }

  // setters
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

    if (_computerMode) handleGameOver(context, chessTimer: chessTimer);
    if (_friendsMode) handleGameOverFriends();

    notifyListeners();
    return result;
  }

  Future<bool> makeStringMove(String bestMove,
      {required BuildContext context, ChessTimer? chessTimer}) async {
    bool result = game.makeMoveString(bestMove);

    if (_computerMode) handleGameOver(context, chessTimer: chessTimer);
    if (_friendsMode) handleGameOverFriends();

    notifyListeners();
    return result;
  }

  // void handleGameOver(BuildContext context, {ChessTimer? chessTimer}) {
  //   if (game.drawn || game.gameOver) {
  //     _isGameEnd = true;
  //     String message = '';
  //     String logo = 'chess_logo.png';
  //     print('game result: ${game.result}');
  //     if (game.drawn) {
  //       if (game.result == 'DrawnGameStalemate' ||
  //           game.result == 'DrawnGameRepetition' ||
  //           game.result == 'DrawnGameBothRoyalsDead' ||
  //           game.result == 'DrawnGameInsufficientMaterial' ||
  //           game.result == '1/2-1/2' ||
  //           game.result == 'DrawnGameElimination') {
  //         message =
  //             "La partie se termine sur un match nul, vous avez tenue tête à l'Ordinateur!";
  //       } else {
  //         message =
  //             "La partie se termine sur un match nul, vous avez tenue tête à l'Ordinateur!";
  //       }
  //     } else if (game.winner == Squares.white) {
  //       message = _playerColor == Squares.white
  //           ? 'Vous avez gagner la partie, bravo!'
  //           : 'L\'ordinateur à gagner la partie, dommage!';
  //       logo = _playerColor == Squares.white
  //           ? 'assets/icons8_crown.png'
  //           : 'assets/icons8_lose.png';
  //     } else if (game.winner == Squares.black) {
  //       message = _playerColor == Squares.black
  //           ? 'Vous avez gagner la partie, bravo!'
  //           : 'L\'ordinateur à gagner la partie, dommage!';
  //       logo = _playerColor == Squares.black
  //           ? 'assets/icons8_crown.png'
  //           : 'assets/icons8_lose.png';
  //     }
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       try {
  //         _isLoading = false;
  //         _friendsMode = false;
  //         _onWillPop = true;
  //         showDialog(
  //           context: context,
  //           barrierDismissible: false,
  //           builder: (BuildContext dialogContext) => CustomAlertDialog(
  //             titleMessage: "Partie Terminée",
  //             subtitleMessage: message,
  //             typeDialog: 0,
  //             logo: logo,
  //           ),
  //         );
  //       } catch (e) {
  //         print('Erreur lors de l\'affichage du dialog: $e');
  //       }
  //     });
  //   }
  // }

  void handleGameOver(BuildContext context, {ChessTimer? chessTimer}) {
    if (game.drawn || game.gameOver) {
      _isGameEnd = true;
      String message = '';
      String logo = 'chess_logo.png';
      print('game result: ${game.result}');

      if (game.result is bishop.DrawnGame) {
        // Gestion détaillée des types de match nul
        if (game.result is bishop.DrawnGameStalemate) {
          message =
              "Pat ! Aucun coup légal n'est possible, la partie est nulle.";
        } else if (game.result is bishop.DrawnGameRepetition) {
          final drawRepetition = game.result as bishop.DrawnGameRepetition;
          message =
              "Nulle par répétition ! La même position s'est répétée ${drawRepetition.repeats} fois.";
        } else if (game.result is bishop.DrawnGameBothRoyalsDead) {
          message = "Nulle ! Les deux rois ont été capturés simultanément.";
        } else if (game.result is bishop.DrawnGameInsufficientMaterial) {
          message =
              "Nulle par matériel insuffisant ! Aucun joueur ne peut gagner.";
        } else if (game.result is bishop.DrawnGameElimination) {
          message = "Nulle par élimination ! Tous les pions ont été éliminés.";
        } else if (game.result is bishop.DrawnGameLength) {
          message =
              "Nulle selon la règle des 50 coups ! Aucune prise ou mouvement de pion.";
        } else if (game.result is bishop.DrawnGamePoints) {
          final drawPoints = game.result as bishop.DrawnGamePoints;
          message =
              "Nulle par points égaux ! Score final : ${drawPoints.points}";
        } else if (game.result is bishop.DrawnGameEnteredRegion) {
          final regionDraw = game.result as bishop.DrawnGameEnteredRegion;
          message =
              "Nulle ! ${bishop.Bishop.playerName[regionDraw.player]} est entré dans une région protégée.";
        } else if (game.result is bishop.DrawnGameExitedRegion) {
          final regionDraw = game.result as bishop.DrawnGameExitedRegion;
          message =
              "Nulle ! ${bishop.Bishop.playerName[regionDraw.player]} est sorti d'une région obligatoire.";
        } else {
          message = "La partie se termine sur un match nul !";
        }
      } else if (game.result is bishop.WonGame) {
        final wonGame = game.result as bishop.WonGame;
        String winReason = '';

        if (game.result is bishop.WonGameCheckmate) {
          winReason = 'par échec et mat';
        } else if (game.result is bishop.WonGameCheckLimit) {
          final checkLimit = game.result as bishop.WonGameCheckLimit;
          winReason = 'en donnant ${checkLimit.numChecks} échecs consécutifs';
        } else if (game.result is bishop.WonGameEnteredRegion) {
          winReason = 'en entrant dans la région gagnante';
        } else if (game.result is bishop.WonGameExitedRegion) {
          winReason = 'en sortant de la région perdante';
        } else if (game.result is bishop.WonGameRoyalDead) {
          winReason = 'par capture du roi adverse';
        } else if (game.result is bishop.WonGameElimination) {
          final elimination = game.result as bishop.WonGameElimination;
          winReason = elimination.pieceType != null
              ? 'par élimination des ${elimination.pieceType}'
              : 'par élimination';
        } else if (game.result is bishop.WonGameStalemate) {
          winReason = 'par pat forcé';
        } else if (game.result is bishop.WonGamePoints) {
          final points = game.result as bishop.WonGamePoints;
          winReason = 'avec un score de ${points.points} points';
        }

        if (wonGame.winner == bishop.Bishop.white) {
          if (_playerColor == bishop.Bishop.white) {
            message = winReason.isEmpty
                ? 'Félicitations ! Vous avez gagné la partie !'
                : 'Félicitations ! Vous avez gagné $winReason !';
          } else {
            message = winReason.isEmpty
                ? "L'ordinateur a gagné la partie, dommage !"
                : "L'ordinateur a gagné $winReason, dommage !";
          }
          logo = _playerColor == Squares.white
              ? 'assets/icons8_crown.png'
              : 'assets/icons8_lose.png';
        } else if (wonGame.winner == Squares.black) {
          if (_playerColor == Squares.black) {
            message = winReason.isEmpty
                ? 'Félicitations ! Vous avez gagné la partie !'
                : 'Félicitations ! Vous avez gagné $winReason !';
          } else {
            message = winReason.isEmpty
                ? "L'ordinateur a gagné la partie, dommage !"
                : "L'ordinateur a gagné $winReason, dommage !";
          }
          logo = _playerColor == Squares.black
              ? 'assets/icons8_crown.png'
              : 'assets/icons8_lose.png';
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _isLoading = false;
          _friendsMode = false;
          _onWillPop = true;

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) => CustomAlertDialog(
              titleMessage: "Partie Terminée",
              subtitleMessage: message,
              typeDialog: 0,
              logo: logo,
            ),
          );
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

  void setOnlineMode({required bool value}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onlineMode = value;
      notifyListeners();
    });
  }

  void setIsloading(bool value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isLoading = value;
      notifyListeners();
    });
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

  void setIsGameEnd({required bool value}) {
    _isGameEnd = value;
    notifyListeners();
  }

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

  void setOpponentUsername({required String username}) {
    _opponentUsername = username;
    notifyListeners();
  }

  // initialize a multiplayer game
  void initializeMultiplayerGame(Map<String, dynamic> gameData) {
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

    _game = bishop.Game(
        variant: bishop.Variant.standard(), fen: _gameModel!.positonFen);

    // Adjust the game state based on player's perspective
    _state = _game.squaresState(_player);

    // Set game mode
    _computerMode = false;
    _friendsMode = true;

    _gameTime = int.tryParse(_gameModel!.whitesTime) ?? 0;

    _isGameEnd = _gameModel!.isGameOver;

    notifyListeners();
  }

  void handleOpponentMove(Map<String, dynamic> moveData) {
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
      _game =
          bishop.Game(variant: bishop.Variant.standard(), fen: moveData['fen']);

      _state = _game.squaresState(_player);
      _gameModel?.isWhitesTurn = moveData['isWhitesTurn'];
      notifyListeners();
    } catch (e) {
      print('Error handling opponent move: $e');
    }
  }

  // void handleGameOverFriends() {
  //   if (game.drawn || game.gameOver) {
  //     _isGameEnd = true;
  //     String winner = '';
  //     if (game.drawn) {
  //       if (game.result == 'DrawnGameStalemate' ||
  //           game.result == 'DrawnGameRepetition' ||
  //           game.result == 'DrawnGameBothRoyalsDead' ||
  //           game.result == 'DrawnGameInsufficientMaterial' ||
  //           game.result == '1/2-1/2' ||
  //           game.result == 'DrawnGameElimination') {
  //         winner = 'Draw';
  //       } else {
  //         winner = 'Draw';
  //       }
  //     } else if (game.winner == Squares.white) {
  //       winner = 'White';
  //     } else if (game.winner == Squares.black) {
  //       winner = 'Black';
  //     }
  //     if (_gameModel != null) {
  //       final gameOverMessage = {
  //         'type': 'game_over_checkmate',
  //         'content': json.encode({
  //           'gameId': _gameModel!.gameId,
  //           'winner': winner,
  //           'winnerId': _isWhiterPlayer
  //               ? winner == 'White'
  //                   ? _gameModel!.gameCreatorUid
  //                   : _gameModel!.userId
  //               : winner == 'Black'
  //                   ? _gameModel!.gameCreatorUid
  //                   : _gameModel!.userId,
  //         }),
  //       };
  //       // Envoyer via WebSocket
  //       WebSocketService().sendMessage(json.encode(gameOverMessage));
  //     }
  //   }
  // }

  void handleGameOverFriends() {
    if (game.drawn || game.gameOver) {
      _isGameEnd = true;
      String winner = '';
      String raison = '';

      if (game.result is bishop.DrawnGame) {
        winner = 'Draw';

        // Déterminer la raison précise du match nul en français
        if (game.result is bishop.DrawnGameStalemate) {
          raison =
              "Pat ! Aucun coup légal n'est possible, la partie est nulle.";
        } else if (game.result is bishop.DrawnGameRepetition) {
          final drawRepetition = game.result as bishop.DrawnGameRepetition;
          raison =
              "Nulle par répétition ! La même position s'est répétée ${drawRepetition.repeats} fois.";
        } else if (game.result is bishop.DrawnGameBothRoyalsDead) {
          raison = "Nulle ! Les deux rois ont été capturés simultanément.";
        } else if (game.result is bishop.DrawnGameInsufficientMaterial) {
          raison =
              "Nulle par matériel insuffisant ! Aucun joueur ne peut gagner.";
        } else if (game.result is bishop.DrawnGameElimination) {
          raison = "Nulle par élimination ! Tous les pions ont été éliminés.";
        } else if (game.result is bishop.DrawnGameLength) {
          raison =
              "Nulle selon la règle des 50 coups ! Aucune prise ou mouvement de pion.";
        } else if (game.result is bishop.DrawnGamePoints) {
          final drawPoints = game.result as bishop.DrawnGamePoints;
          raison =
              "Nulle par points égaux ! Score final : ${drawPoints.points}";
        } else if (game.result is bishop.DrawnGameEnteredRegion) {
          final regionDraw = game.result as bishop.DrawnGameEnteredRegion;
          raison =
              "Nulle ! ${bishop.Bishop.playerName[regionDraw.player]} est entré dans une région protégée.";
        } else if (game.result is bishop.DrawnGameExitedRegion) {
          final regionDraw = game.result as bishop.DrawnGameExitedRegion;
          raison =
              "Nulle ! ${bishop.Bishop.playerName[regionDraw.player]} est sorti d'une région obligatoire.";
        } else {
          raison = "La partie se termine sur un match nul !";
        }
      } else if (game.result is bishop.WonGame) {
        final wonGame = game.result as bishop.WonGame;
        winner = wonGame.winner == bishop.Bishop.white ? 'White' : 'Black';

        // Déterminer la raison précise de la victoire en français
        if (game.result is bishop.WonGameCheckmate) {
          raison = 'par échec et mat';
        } else if (game.result is bishop.WonGameCheckLimit) {
          final checkLimit = game.result as bishop.WonGameCheckLimit;
          raison = 'en donnant ${checkLimit.numChecks} échecs consécutifs';
        } else if (game.result is bishop.WonGameEnteredRegion) {
          raison = 'en entrant dans la région gagnante';
        } else if (game.result is bishop.WonGameExitedRegion) {
          raison = 'en sortant de la région perdante';
        } else if (game.result is bishop.WonGameRoyalDead) {
          raison = 'par capture du roi adverse';
        } else if (game.result is bishop.WonGameElimination) {
          final elimination = game.result as bishop.WonGameElimination;
          raison = elimination.pieceType != null
              ? 'par élimination des ${elimination.pieceType}'
              : 'par élimination';
        } else if (game.result is bishop.WonGameStalemate) {
          raison = 'par pat forcé';
        } else if (game.result is bishop.WonGamePoints) {
          final points = game.result as bishop.WonGamePoints;
          raison = 'avec un score de ${points.points} points';
        }
      }

      if (_gameModel != null) {
        final gameOverMessage = {
          'type': 'game_over_checkmate',
          'content': json.encode({
            'gameId': _gameModel!.gameId,
            'winner': winner,
            'reason': raison,
            'winnerId': _isWhiterPlayer
                ? winner == 'White'
                    ? _gameModel!.gameCreatorUid
                    : _gameModel!.userId
                : winner == 'Black'
                    ? _gameModel!.gameCreatorUid
                    : _gameModel!.userId,
          }),
        };

        // Envoyer via WebSocket
        WebSocketService().sendMessage(json.encode(gameOverMessage));
      }
    }
  }

  void setOnWillPop({required bool value}) => _onWillPop = value;

// Online users and invitations
  List<UserProfile> _onlineUsers = [];
  // ignore: prefer_final_fields
  List<InvitationMessage> _invitations = [];
  InvitationMessage? _currentInvitation;

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

  void updateOnlineUsers(List<UserProfile> users) {
    _onlineUsers = users.toSet().toList();
    _onlineUsersController.add(_onlineUsers);
    notifyListeners();
  }

  void addInvitation(InvitationMessage invitation) {
    // Supprimer d'abord toute invitation existante du même utilisateur
    _invitations.removeWhere((inv) =>
        inv.fromUserId == invitation.fromUserId ||
        inv.toUserId == invitation.fromUserId);

    // Ajouter la nouvelle invitation
    _invitations.add(invitation);
    _invitationsController.add(_invitations);
    setInvitationCancel(value: false);
    notifyListeners();
  }

  void removeInvitation(InvitationMessage invitation) {
    _invitations.removeWhere((inv) =>
        inv.fromUserId == invitation.fromUserId &&
        inv.toUserId == invitation.toUserId);
    _invitationsController.add(_invitations);
    setInvitationCancel(value: false);
    notifyListeners();
  }

  void clearInvitations() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _invitations.clear();
      _invitationsController.add(_invitations);
      setInvitationCancel(value: false);
      _currentInvitation = null;
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

  void handleInvitationRejection(
      BuildContext context, InvitationMessage invitation) {
    showCustomSnackBarBottom(
        context, '${invitation.fromUsername} a rejeter  votre invitation');

    Navigator.pushReplacement(
        context, CustomPageRoute(child: const FriendListScreen()));
  }

  bool _invitationTimeOut = false;
  bool _cancelWaintingRoom = false;
  bool _invitationRejct = false;

  bool get invitationTimeOut => _invitationTimeOut;
  bool get invitationRejct => _invitationRejct;
  bool get cancelWaintingRoom => _cancelWaintingRoom;

  void setInvitationTimeOut({required bool value}) {
    _invitationTimeOut = value;
    notifyListeners();
  }

  void setCancelWaintingRoom({required bool value}) {
    _cancelWaintingRoom = value;
    notifyListeners();
  }

  void setInvitationRejct({required bool value}) {
    _invitationRejct = value;
    notifyListeners();
  }

  void setInvitationCancel({required bool value}) {
    _invitationCancel = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _onlineUsersController.close();
    _invitationsController.close();
    super.dispose();
  }
}
