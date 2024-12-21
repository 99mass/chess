import 'dart:async';
import 'dart:convert';
import 'package:chess/constant/constants.dart';
import 'package:chess/model/invitation_model.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/provider/time_provider.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/services/web_socket_service.dart';
import 'package:chess/utils/helper.dart';
import 'package:chess/utils/stockfish_uic_command.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:squares/squares.dart';
import 'package:stockfish/stockfish.dart';

class GameBoardScreen extends StatefulWidget {
  const GameBoardScreen({super.key});

  @override
  State<GameBoardScreen> createState() => _GameBoardScreenState();
}

class _GameBoardScreenState extends State<GameBoardScreen> {
  late WebSocketService _webSocketService;
  late GameProvider _gameProvider;
  late Stockfish? stockfish;
  late ChessTimer _chessTimer;
  StreamSubscription<String>? _stockfishSubscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _gameProvider = context.read<GameProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _webSocketService = WebSocketService();
      _webSocketService.connectWebSocket(context);
    });

    // Initialize stockfish only for computer mode
    stockfish = _gameProvider.computerMode ? StockfishInstance.instance : null;
    _gameProvider.resetGame(newGame: false);

    _chessTimer = ChessTimer(
      initialMinutes: _gameProvider.gameTime,
      startWithWhite: _gameProvider.playerColor == PlayerColor.white,
      onTimeExpired: () {
        _chessTimer.reset();
      },
      onTimerUpdate: () {
        setState(() {});
      },
    );

    _chessTimer.start(
      context: context,
      playerColor: _gameProvider.playerColor,
    );

    // Handle first move based on game mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gameProvider.computerMode) {
        letOtherPlayerPlayFirst();
      }
    });
  }

  Future<void> waitUntilReady({int timeoutSeconds = 10}) async {
    if (stockfish == null) return;

    int elapsed = 0;
    while (stockfish!.state.value != StockfishState.ready) {
      if (elapsed >= timeoutSeconds) {
        debugPrint('Timeout: Stockfish n\'est pas prêt.');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      elapsed++;
    }
  }

  void _onMove(Move move) async {
    _gameProvider = context.read<GameProvider>();

    // Pour le mode ami (multiplayer)
    if (_gameProvider.friendsMode) {
      bool result = await _gameProvider.makeSquaresMove(move, context: context);

      if (result) {
        _gameProvider.setIsMyTurn(value: false);
        _gameProvider.setIsOpponentTurn(value: true);

        final moveData = {
          'gameId': _gameProvider.gameId,
          'fromUserId': _gameProvider.user.id,
          'toUserId': _gameProvider.gameModel?.userId ?? '',
          'toUsername': _gameProvider.gameModel?.opponentUsername ?? '',
          // ignore: unnecessary_null_comparison
          'move': move == null
              ? null
              : {
                  'from': move.from,
                  'to': move.to,
                  'promo': move.promo,
                },
          'fen': _gameProvider.getPositionFen(),
          'isWhitesTurn': !_gameProvider.gameModel!.isWhitesTurn,
        };

        _webSocketService.sendMessage(json
            .encode({'type': 'game_move', 'content': json.encode(moveData)}));

        // Met à jour l'état du jeu
        await _gameProvider.setSquareState();
      }
    }
    // Pour le mode ordinateur
    else if (_gameProvider.computerMode) {
      bool result = await _gameProvider.makeSquaresMove(move, context: context);
      if (result) {
        _chessTimer.switchTurn();

        _gameProvider.setSquareState().whenComplete(() {
          if (_gameProvider.state.state == PlayState.theirTurn &&
              !_gameProvider.aiThinking) {
            _triggerAiMove();
          }
        });
      }
    }
  }

  void letOtherPlayerPlayFirst() async {
    if (_gameProvider.computerMode &&
        _gameProvider.state.state == PlayState.theirTurn &&
        !_gameProvider.aiThinking) {
      _triggerAiMove();
    }
  }

  void _triggerAiMove() async {
    if (stockfish == null) return;

    await waitUntilReady();

    if (stockfish!.state.value != StockfishState.ready) {
      debugPrint('Stockfish n\'est pas prêt à exécuter des commandes.');
      return;
    }

    _gameProvider.setAiThinking(true);

    int gameLevel = switch (_gameProvider.gameDifficulty) {
      GameDifficulty.easy => 1,
      GameDifficulty.medium => 2,
      GameDifficulty.hard => 3,
    };

    // Envoyer les commandes à Stockfish
    stockfish!.stdin =
        '${StockfishUicCommand.position} ${_gameProvider.getPositionFen()}';
    stockfish!.stdin = '${StockfishUicCommand.goMoveTime} ${gameLevel * 1000}';

    // Désabonner les anciens écouteurs s'il y en a
    _stockfishSubscription?.cancel();

    // Écouter les réponses de Stockfish
    _stockfishSubscription = stockfish!.stdout.listen((event) {
      if (event.contains(StockfishUicCommand.bestMove)) {
        final bestMove = event.split(' ')[1];

        // Vérifier si le jeu est terminé ou si ce n'est pas le bon tour
        if (_gameProvider.state.state != PlayState.theirTurn) return;

        _gameProvider.makeStringMove(bestMove, context: context);
        _gameProvider.setAiThinking(false);
        _gameProvider.setSquareState().whenComplete(() {
          _chessTimer.switchTurn();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _gameProvider = context.read<GameProvider>();
    if (_gameProvider.isGameEnd) {
      _chessTimer.stop();
      _chessTimer.dispose();
    }
    if (_gameProvider.exitGame) {
      _chessTimer.stop();
      _chessTimer.dispose();
      _timer?.cancel();
      if (stockfish != null) {
        stockfish!.stdin = StockfishUicCommand.stop;
        _webSocketService.disposeInvitationStream();
        _stockfishSubscription?.cancel();
      }

      _gameProvider.resetGame(newGame: true);

      Timer(const Duration(seconds: 1), () {});
      Future.microtask(() => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const MainMenuScreen(),
            ),
          ));
    }

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        bool? confirmExit = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return _ConfirmExitDialog();
          },
        );

        if (confirmExit == true) {
          _cleanup();

          Timer(const Duration(seconds: 2), () {});
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const MainMenuScreen(),
            ),
          );

          return true;
        }

        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Determine board size based on screen constraints
          double boardSize = constraints.maxWidth > constraints.maxHeight
              ? constraints.maxHeight * 0.8
              : constraints.maxWidth * 0.9;

          return Scaffold(
              backgroundColor: Colors.black54,
              appBar: AppBar(
                title: Text(
                  _gameProvider.computerMode
                      ? 'Computer Game'
                      : _gameProvider.friendsMode
                          ? 'Multiplayer Game'
                          : 'Chess Game',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                automaticallyImplyLeading: false,
                backgroundColor: Colors.amber[700],
                actions: [
                  IconButton(
                    onPressed: () {
                      _chessTimer.reset();
                      _gameProvider.resetGame(newGame: false);
                      if (mounted) {
                        if (_gameProvider.computerMode) {
                          letOtherPlayerPlayFirst();
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.restart_alt,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              body: Consumer<GameProvider>(
                  builder: (context, gameProvider, child) {
                String whiteRemainingTime = getTimerToDisplay(
                    gameProvider: gameProvider,
                    chessTimer: _chessTimer,
                    isUser: true);
                String blackRemainingTime = getTimerToDisplay(
                    gameProvider: gameProvider,
                    chessTimer: _chessTimer,
                    isUser: false);

                return Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // User 2 (Top Player)
                        SizedBox(
                          width: boardSize,
                          child: _buildUserTile(
                            email: _getPlayerName(
                                isWhite: !gameProvider.isWhitePlayer),
                            avatarUrl: 'avatar.png',
                            isTurn: gameProvider.friendsMode
                                ? _gameProvider.isOpponentTurn
                                : !_chessTimer.isWhiteTurn,
                            tileColor: Colors.white,
                            textColor: Colors.black,
                            timer: blackRemainingTime,
                          ),
                        ),
                        // Game Board
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 12.0,
                          ),
                          // Friends Mode
                          child: gameProvider.friendsMode
                              ? SizedBox(
                                  width: boardSize,
                                  height: boardSize,
                                  child: BoardController(
                                    state: gameProvider.isWhitePlayer
                                        ? gameProvider.state.board.flipped()
                                        : gameProvider.state.board,
                                    playState: gameProvider.state.state,
                                    pieceSet: PieceSet.merida(),
                                    theme: BoardTheme.blueGrey,
                                    moves: gameProvider.state.moves,
                                    onMove: _onMove,
                                    onPremove: _onMove,
                                    markerTheme: MarkerTheme(
                                      empty: MarkerTheme.dot,
                                      piece: MarkerTheme.corners(),
                                    ),
                                    promotionBehaviour:
                                        PromotionBehaviour.autoPremove,
                                  ),
                                )
                              // Computer Mode
                              : SizedBox(
                                  width: boardSize,
                                  height: boardSize,
                                  child: BoardController(
                                    state: gameProvider.flipBoard
                                        ? gameProvider.state.board.flipped()
                                        : gameProvider.state.board,
                                    playState: gameProvider.state.state,
                                    pieceSet: PieceSet.merida(),
                                    theme: BoardTheme.blueGrey,
                                    moves: gameProvider.state.moves,
                                    onMove: _onMove,
                                    onPremove: _onMove,
                                    markerTheme: MarkerTheme(
                                      empty: MarkerTheme.dot,
                                      piece: MarkerTheme.corners(),
                                    ),
                                    promotionBehaviour:
                                        PromotionBehaviour.autoPremove,
                                  ),
                                ),
                        ),
                        // User 1 (Bottom Player)
                        SizedBox(
                          width: boardSize,
                          child: _buildUserTile(
                            email: _getPlayerName(
                                isWhite: gameProvider.isWhitePlayer),
                            avatarUrl: 'avatar.png',
                            isTurn: gameProvider.friendsMode
                                ? _gameProvider.isMyTurn
                                : _chessTimer.isWhiteTurn,
                            tileColor: Colors.white,
                            textColor: Colors.black,
                            timer: whiteRemainingTime,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }));
        },
      ),
    );
  }

  void _cleanup() {
    // Stop and dispose of the chess timer
    _chessTimer.stop();
    _chessTimer.dispose();

    // Cancel any running timers
    _timer?.cancel();

    // Stop Stockfish if it's running
    if (stockfish != null) {
      // Cancel Stockfish subscription
      _stockfishSubscription?.cancel();
      stockfish!.stdin = StockfishUicCommand.stop;
    }

    // Handle WebSocket room leaving for multiplayer mode
    if (_gameProvider.friendsMode) {
      final roomLeave = InvitationMessage(
        type: 'room_leave',
        fromUserId: _gameProvider.user.id,
        fromUsername: _gameProvider.user.userName,
        toUserId: _gameProvider.gameModel!.userId,
        toUsername: _gameProvider.opponentUsername,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        roomId: _gameProvider.gameModel!.gameId,
      );

      final roomLeaveJson = json.encode(
          {'type': 'room_leave', 'content': json.encode(roomLeave.toJson())});
      _gameProvider.setGameModel();
      _gameProvider.setCurrentInvitation();

      _webSocketService.sendMessage(roomLeaveJson);
    }

    // Dispose of WebSocket invitation stream
    _webSocketService.disposeInvitationStream();

    // Reset game state
    _gameProvider.resetGame(newGame: true);
  }

  String _getPlayerName({required bool isWhite}) {
    if (_gameProvider.computerMode) {
      return !isWhite ? 'You' : 'Computer';
    } else if (_gameProvider.friendsMode && _gameProvider.gameModel != null) {
      return isWhite
          ? _gameProvider.gameModel!.opponentUsername
          : _gameProvider.user.userName;
    }
    return isWhite ? 'Player 1' : 'Player 2';
  }

  Widget _buildUserTile(
      {required String email,
      required String avatarUrl,
      required bool isTurn,
      required Color tileColor,
      required Color textColor,
      required String timer}) {
    return ListTile(
      tileColor: tileColor,
      leading: CircleAvatar(
        backgroundImage: AssetImage(
          'assets/$avatarUrl',
        ),
        radius: 20,
        child: Align(
          alignment: Alignment.topRight,
          child: Container(
            decoration: BoxDecoration(
              color: isTurn ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
      title: Text(
        email.split('@')[0],
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.access_time,
            color: Colors.black,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            timer,
            style: TextStyle(
              color:
                  int.parse(timer.split(':')[0]) <= 1 ? Colors.red : textColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: non_constant_identifier_names
  Widget _ConfirmExitDialog() {
    return AlertDialog(
      title: const Text('Exit Game'),
      content: const Text('Are you sure you want to exit the game?'),
      actions: [
        TextButton(
          child: const Text('No'),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          child: const Text('Yes'),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    // Store the reference safely here
    _gameProvider = Provider.of<GameProvider>(context, listen: false);
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _chessTimer.stop();
    _chessTimer.dispose();

    _timer?.cancel();

    if (stockfish != null) {
      stockfish!.stdin = StockfishUicCommand.stop;
      _stockfishSubscription?.cancel();
    }

    if (_gameProvider.friendsMode) {
      _gameProvider.setGameModel();
      _gameProvider.setCurrentInvitation();
    }
    _webSocketService.disposeInvitationStream();
    _gameProvider.resetGame(newGame: true);

    super.dispose();
  }
}
