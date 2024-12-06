import 'dart:async';
import 'package:chess/constant/constants.dart';
import 'package:chess/provider/game_provider.dart';
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
  late Stockfish stockfish;
  late GameProvider gameProvider;
  late ChessTimer _chessTimer;
  StreamSubscription<String>? _stockfishSubscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    stockfish = StockfishInstance.instance;

    gameProvider = context.read<GameProvider>();
    gameProvider.resetGame(newGame: false);

    _chessTimer = ChessTimer(
      initialMinutes: gameProvider.gameTime,
      startWithWhite: gameProvider.playerColor == PlayerColor.white,
      onTimeExpired: () {
        _chessTimer.reset();
      },
      onTimerUpdate: () {
        setState(() {});
      },
    );

    _chessTimer.start(
      context: context,
      playerColor: gameProvider.playerColor,
    );

    // Assurez-vous que le jeu est prêt avant de laisser l'IA jouer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      letOtherPlayerPlayFirst();
    });
  }

  Future<void> waitUntilReady({int timeoutSeconds = 10}) async {
    int elapsed = 0;
    while (stockfish.state.value != StockfishState.ready) {
      if (elapsed >= timeoutSeconds) {
        debugPrint('Timeout: Stockfish n\'est pas prêt.');
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
      elapsed++;
    }
  }

  void _onMove(Move move) async {
    gameProvider = context.read<GameProvider>();

    Future<bool> result = gameProvider.makeSquaresMove(move, context: context);
    if (await result) {
      _chessTimer.switchTurn();
      gameProvider.setSquareState().whenComplete(() {
        if (gameProvider.state.state == PlayState.theirTurn &&
            !gameProvider.aiThinking) {
          _triggerAiMove();
        }
      });
    }
  }

  void letOtherPlayerPlayFirst() async {
    if (gameProvider.state.state == PlayState.theirTurn &&
        !gameProvider.aiThinking) {
      _triggerAiMove();
    }
  }

  void _triggerAiMove() async {
    await waitUntilReady();

    if (stockfish.state.value != StockfishState.ready) {
      debugPrint('Stockfish n\'est pas prêt à exécuter des commandes.');
      return;
    }

    gameProvider.setAiThinking(true);

    int gameLevel = switch (gameProvider.gameDifficulty) {
      GameDifficulty.easy => 1,
      GameDifficulty.medium => 2,
      GameDifficulty.hard => 3,
    };

    // Envoyer les commandes à Stockfish
    stockfish.stdin =
        '${StockfishUicCommand.position} ${gameProvider.getPositionFen()}';
    stockfish.stdin = '${StockfishUicCommand.goMoveTime} ${gameLevel * 1000}';

    // Désabonner les anciens écouteurs s'il y en a
    _stockfishSubscription?.cancel();

    // Écouter les réponses de Stockfish
    _stockfishSubscription = stockfish.stdout.listen((event) {
      if (event.contains(StockfishUicCommand.bestMove)) {
        final bestMove = event.split(' ')[1];

        // Vérifier si le jeu est terminé ou si ce n'est pas le bon tour
        if (gameProvider.state.state != PlayState.theirTurn) return;

        gameProvider.makeStringMove(bestMove, context: context);
        gameProvider.setAiThinking(false);
        gameProvider.setSquareState().whenComplete(() {
          _chessTimer.switchTurn();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    gameProvider = context.read<GameProvider>();

    if (gameProvider.isGameEnd) {
      _chessTimer.stop();
      _chessTimer.dispose();
    }

    return WillPopScope(
      onWillPop: () async {
        bool? confirmExit = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return _ConfirmExitDialog();
          },
        );

        if (confirmExit == true) {
          // Libération des ressources
          _timer?.cancel();
          _chessTimer.dispose();
          _chessTimer.stop();
          stockfish.stdin = StockfishUicCommand.stop;
          _stockfishSubscription?.cancel();
          return true; // Autorise la sortie
        }

        return false; // Bloque la sortie
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
                title: const Text(
                  'Chess Game',
                  style: TextStyle(
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
                      gameProvider.resetGame(newGame: false);
                      if (mounted) {
                        letOtherPlayerPlayFirst();
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
                        // User 2
                        SizedBox(
                          width: boardSize,
                          child: _buildUserTile(
                            email: 'master@chess.com',
                            avatarUrl: 'avatar.png',
                            isTurn: !_chessTimer.isWhiteTurn,
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
                          child: SizedBox(
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
                        // User 1
                        SizedBox(
                          width: boardSize,
                          child: _buildUserTile(
                            email: 'breukh@chess.com',
                            avatarUrl: 'avatar.png',
                            isTurn: _chessTimer.isWhiteTurn,
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
  void dispose() {
    _chessTimer.stop();
    _chessTimer.dispose();
    _timer?.cancel();
    stockfish.stdin = StockfishUicCommand.stop;
    _stockfishSubscription?.cancel();
    super.dispose();
  }
}
