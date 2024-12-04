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

  Timer? _timer;

  @override
  void initState() {
    gameProvider = context.read<GameProvider>();
    gameProvider.resetGame(newGame: false);
    if (mounted) {
      stockfish = Stockfish();
      letOtherPlayerPlayFirst();
    }
    super.initState();
    _chessTimer = ChessTimer(
        initialMinutes: gameProvider.gameTime,
        startWithWhite: gameProvider.playerColor == PlayerColor.white,
        onTimeExpired: () {
          _chessTimer.reset();
        },
        onTimerUpdate: () {
          setState(() {});
        });
    _chessTimer.start(context: context, playerColor: gameProvider.playerColor);
  }

  void letOtherPlayerPlayFirst() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      gameProvider = context.read<GameProvider>();
      if (gameProvider.state.state == PlayState.theirTurn &&
          !gameProvider.aiThinking) {
        gameProvider.setAiThinking(true);

        int gameLevel = switch (gameProvider.gameDifficulty) {
          GameDifficulty.easy => 1,
          GameDifficulty.medium => 2,
          GameDifficulty.hard => 3,
        };

        await waitUntilReady();

        stockfish.stdin =
            '${StockfishUicCommand.position} ${gameProvider.getPositionFen()}';

        stockfish.stdin =
            '${StockfishUicCommand.goMoveTime} ${gameLevel * 1000}';

        stockfish.stdout.listen((event) {
          if (event.contains(StockfishUicCommand.bestMove)) {
            final bestMove = event.split(' ')[1];
            gameProvider.makeStringMove(bestMove);
            gameProvider.setAiThinking(false);
            gameProvider.setSquareState().whenComplete(() {
              _chessTimer.switchTurn();
            });
          }
        });
      }
    });
  }

  void _onMove(Move move) async {
    print('move: ${move.toString()}');
    print('String move: ${move.algebraic()}');
    gameProvider = context.read<GameProvider>();

    Future<bool> result = gameProvider.makeSquaresMove(move, context: context);
    if (await result) {
      gameProvider.setSquareState().whenComplete(() {
        _chessTimer.switchTurn();
      });
    }

    if (gameProvider.state.state == PlayState.theirTurn &&
        !gameProvider.aiThinking) {
      gameProvider.setAiThinking(true);

      int gameLevel = switch (gameProvider.gameDifficulty) {
        GameDifficulty.easy => 1,
        GameDifficulty.medium => 2,
        GameDifficulty.hard => 3,
      };

      await waitUntilReady();

      stockfish.stdin =
          '${StockfishUicCommand.position} ${gameProvider.getPositionFen()}';

      stockfish.stdin = '${StockfishUicCommand.goMoveTime} ${gameLevel * 1000}';

      stockfish.stdout.listen((event) {
        if (event.contains(StockfishUicCommand.bestMove)) {
          final bestMove = event.split(' ')[1];

          gameProvider.makeStringMove(bestMove);
          gameProvider.setAiThinking(false);
          gameProvider.setSquareState().whenComplete(() {
            _chessTimer.switchTurn();
          });
        }
      });
    }
  }

  Future<void> waitUntilReady() async {
    while (stockfish.state.value != StockfishState.ready) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chessTimer.dispose();
    stockfish.stdin = StockfishUicCommand.stop;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    gameProvider = context.read<GameProvider>();

    return LayoutBuilder(
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
            body:
                Consumer<GameProvider>(builder: (context, gameProvider, child) {
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
                            promotionBehaviour: PromotionBehaviour.autoPremove,
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
}
