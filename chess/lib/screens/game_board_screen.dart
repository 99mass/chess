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
import 'package:chess/widgets/custom_alert_dialog.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
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

    if (_gameProvider.computerMode) {
      _chessTimer.start(
        context: context,
        playerColor: _gameProvider.playerColor,
      );
    }

    // Handle first move based on game mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_gameProvider.computerMode) {
        _gameProvider.setIsloading(true);
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

  void letOtherPlayerPlayFirst2() async {
    if (_gameProvider.computerMode &&
        !_gameProvider.aiThinking &&
        _gameProvider.playerColor == PlayerColor.black) {
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
      _gameProvider.setIsloading(false);
    }
    if (_gameProvider.exitGame) {
      _gameProvider.setIsloading(false);
      _chessTimer.stop();
      _chessTimer.dispose();
      _timer?.cancel();
      _timer = null;
      _gameProvider.setFriendsMode(value: false);
      if (stockfish != null) {
        stockfish!.stdin = StockfishUicCommand.stop;
        _webSocketService.disposeInvitationStream();
        _stockfishSubscription?.cancel();
        stockfish = null;
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
        return exitGame0();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          double boardSize = constraints.maxWidth;

          return Scaffold(
              backgroundColor: ColorsConstants.colorBg,
              appBar: AppBar(
                automaticallyImplyLeading: true,
                backgroundColor: ColorsConstants.colorBg,
                leading: IconButton(
                  icon: Image.asset(
                    'assets/icons8_arrow_back.png',
                    width: 30,
                  ),
                  onPressed: () async {
                    exitGame();
                  },
                ),
                actions: [
                  if (_gameProvider.computerMode && _gameProvider.isGameEnd)
                    IconButton(
                      onPressed: () {
                        restartGame();
                      },
                      icon: Image.asset(
                        'assets/icons8_restart.png',
                        width: 40,
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

                return SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.symmetric(vertical: 20.0),
                        decoration: const BoxDecoration(
                          image: DecorationImage(
                            image: AssetImage('assets/chess_logo.png'),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      // User 2 (Top Player)
                      SizedBox(
                        width: boardSize,
                        child: _buildUserTile(
                            name: _getPlayerName(
                                isWhite: !gameProvider.isWhitePlayer),
                            avatarUrl: gameProvider.friendsMode
                                ? 'avatar.png'
                                : 'icons8_ai.png',
                            isTurn: gameProvider.friendsMode
                                ? _gameProvider.isOpponentTurn
                                : !_chessTimer.isWhiteTurn,
                            timer: blackRemainingTime,
                            size: boardSize),
                      ),
                      // Game Board
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 15.0,
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
                            name: _getPlayerName(
                                isWhite: gameProvider.isWhitePlayer),
                            avatarUrl: 'avatar.png',
                            isTurn: gameProvider.friendsMode
                                ? _gameProvider.isMyTurn
                                : _chessTimer.isWhiteTurn,
                            timer: whiteRemainingTime,
                            size: boardSize),
                      ),
                    ],
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
    _timer = null;

    // Stop Stockfish if it's running
    if (stockfish != null) {
      // Cancel Stockfish subscription
      _stockfishSubscription?.cancel();
      stockfish!.stdin = StockfishUicCommand.stop;
      stockfish = null;
    }

    // Handle WebSocket room leaving for multiplayer mode
    if (_gameProvider.friendsMode) {
      final roomLeave = InvitationMessage(
        type: 'room_leave',
        fromUserId: _gameProvider.user.id,
        fromUsername: _gameProvider.user.userName,
        toUserId: _gameProvider.gameModel!.userId,
        toUsername: _gameProvider.opponentUsername,
        roomId: _gameProvider.gameModel!.gameId,
      );

      final roomLeaveJson = json.encode(
          {'type': 'room_leave', 'content': json.encode(roomLeave.toJson())});
      _gameProvider.setGameModel();
      _gameProvider.setCurrentInvitation();

      _webSocketService.sendMessage(roomLeaveJson);
    }
    _gameProvider.setIsloading(false);
    // Dispose of WebSocket invitation stream
    _webSocketService.disposeInvitationStream();

    // Reset game state
    _gameProvider.resetGame(newGame: true);
  }

  void exitGame() async {
    if (!_gameProvider.onWillPop) {
      bool? confirmExit = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return const CustomAlertDialog(
            titleMessage: "Quitter la partie ?",
            subtitleMessage:
                "Êtes-vous sûr de vouloir abandonner la partie en cours ?",
                simpleDialog: false,
          );
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
      }
    }

    if (_gameProvider.onWillPop) {
      _cleanup();
      _gameProvider.setOnWillPop(value: false);
      _gameProvider.setGameModel();

      Timer(const Duration(seconds: 2), () {});
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MainMenuScreen(),
        ),
      );
    }
  }

  Future<bool> exitGame0() async {
    if (!_gameProvider.onWillPop) {
      bool? confirmExit = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return const CustomAlertDialog(
            titleMessage: "Quitter la partie ?",
            subtitleMessage:
                "Êtes-vous sûr de vouloir abandonner la partie en cours ?",
                simpleDialog: false,
          );
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
    }

    if (_gameProvider.onWillPop) {
      _cleanup();
      _gameProvider.setOnWillPop(value: false);
      _gameProvider.setGameModel();

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
  }

  void restartGame() async {
    _gameProvider.setOnWillPop(value: false);
    _chessTimer.reset();
    _gameProvider.resetGame(newGame: false);
    if (mounted) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chessTimer.start(
          context: context,
          playerColor: _gameProvider.playerColor,
        );
        _gameProvider.setIsloading(true);
        _gameProvider.setIsGameEnd(value: false);
        _gameProvider.setIsloading(true);
        letOtherPlayerPlayFirst();
      });
    }
  }

  String _getPlayerName({required bool isWhite}) {
    if (_gameProvider.computerMode) {
      return !isWhite ? _gameProvider.user.userName : 'Ordinateur';
    }
    return isWhite
        ? _gameProvider.gameModel?.opponentUsername ?? ''
        : _gameProvider.user.userName;
  }

  Widget _buildUserTile(
      {required String name,
      required String avatarUrl,
      required bool isTurn,
      required String timer,
      required double size}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Image(
              image: AssetImage(
                'assets/$avatarUrl',
              ),
              width: 60,
              height: 60,
            ),
            const SizedBox(width: 10),
            Text(
              name,
              style: const TextStyle(
                fontSize: 22,
                color: ColorsConstants.white,
              ),
            ),
          ],
        ),
        Row(
          children: [
            if (isTurn && _gameProvider.isloading && !_gameProvider.isGameEnd)
              const CustomImageSpinner(
                size: 30.0,
                duration: Duration(milliseconds: 2000),
              ),
            const SizedBox(width: 10),
            Container(
              alignment: Alignment.center,
              width: 100,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: isTurn
                    ? ColorsConstants.colorGreen
                    : ColorsConstants.colorBg2,
              ),
              child: Text(
                timer,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ColorsConstants.white,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
            )
          ],
        )
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
    _timer = null;

    if (stockfish != null) {
      stockfish!.stdin = StockfishUicCommand.stop;
      _stockfishSubscription?.cancel();
      stockfish = null;
    }

    if (_gameProvider.friendsMode) {
      _gameProvider.setGameModel();
      _gameProvider.setCurrentInvitation();
    }
    _gameProvider.setIsloading(false);
    _webSocketService.disposeInvitationStream();
    _gameProvider.resetGame(newGame: true);

    super.dispose();
  }
}
