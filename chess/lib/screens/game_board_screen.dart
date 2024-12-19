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
  late Stockfish? stockfish;
  late GameProvider gameProvider;
  late ChessTimer _chessTimer;
  StreamSubscription<String>? _stockfishSubscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _webSocketService = WebSocketService();
    _webSocketService.connectWebSocket(context);
    gameProvider = context.read<GameProvider>();

    // Initialize stockfish only for computer mode
    stockfish = gameProvider.computerMode ? StockfishInstance.instance : null;
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

    // Handle first move based on game mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (gameProvider.computerMode) {
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
    gameProvider = context.read<GameProvider>();

    Future<bool> result = gameProvider.makeSquaresMove(move, context: context);
    if (await result) {
      _chessTimer.switchTurn();

      // Determine next action based on game mode
      if (gameProvider.computerMode) {
        gameProvider.setSquareState().whenComplete(() {
          if (gameProvider.state.state == PlayState.theirTurn &&
              !gameProvider.aiThinking) {
            _triggerAiMove();
          }
        });
      } else if (gameProvider.friendsMode) {
        // First, attempt to make the move locally
        Future<bool> result =
            gameProvider.makeSquaresMove(move, context: context);

        if (await result) {
          _chessTimer.switchTurn();

          // Send move via WebSocket
          _webSocketService.sendGameMove(gameProvider, move);

          // Update game state
          gameProvider.setSquareState().whenComplete(() {
            // Additional state management if needed
          });
        }
      }
    }
  }

  void letOtherPlayerPlayFirst() async {
    if (gameProvider.computerMode &&
        gameProvider.state.state == PlayState.theirTurn &&
        !gameProvider.aiThinking) {
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

    gameProvider.setAiThinking(true);

    int gameLevel = switch (gameProvider.gameDifficulty) {
      GameDifficulty.easy => 1,
      GameDifficulty.medium => 2,
      GameDifficulty.hard => 3,
    };

    // Envoyer les commandes à Stockfish
    stockfish!.stdin =
        '${StockfishUicCommand.position} ${gameProvider.getPositionFen()}';
    stockfish!.stdin = '${StockfishUicCommand.goMoveTime} ${gameLevel * 1000}';

    // Désabonner les anciens écouteurs s'il y en a
    _stockfishSubscription?.cancel();

    // Écouter les réponses de Stockfish
    _stockfishSubscription = stockfish!.stdout.listen((event) {
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
    if (gameProvider.exitGame) {
      _chessTimer.stop();
      _chessTimer.dispose();
      _timer?.cancel();
      if (stockfish != null) {
        stockfish!.stdin = StockfishUicCommand.stop;
      }

      _webSocketService.disposeInvitationStream();
      _stockfishSubscription?.cancel();
      gameProvider.resetGame(newGame: true);

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
                  gameProvider.computerMode
                      ? 'Computer Game'
                      : gameProvider.friendsMode
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
                      gameProvider.resetGame(newGame: false);
                      if (mounted) {
                        if (gameProvider.computerMode) {
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

  void _cleanup() {
    // Stop and dispose of the chess timer
    _chessTimer.stop();
    _chessTimer.dispose();

    // Cancel any running timers
    _timer?.cancel();

    // Stop Stockfish if it's running
    if (stockfish != null) {
      stockfish!.stdin = StockfishUicCommand.stop;
    }

    // Cancel Stockfish subscription
    _stockfishSubscription?.cancel();

    // Handle WebSocket room leaving for multiplayer mode
    if (gameProvider.friendsMode) {
      final roomLeave = InvitationMessage(
        type: 'room_leave',
        fromUserId: gameProvider.user.id,
        fromUsername: gameProvider.user.userName,
        toUserId: gameProvider.gameModel!.userId,
        toUsername: gameProvider.opponentUsername,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        roomId: gameProvider.gameModel!.gameId,
      );

      final roomLeaveJson = json.encode(
          {'type': 'room_leave', 'content': json.encode(roomLeave.toJson())});
      gameProvider.setGameModel();
      gameProvider.setCurrentInvitation();
      // gameProvider.setIsFlipBoard(value: false);
      // gameProvider.setFriendsMode(value: false);

      _webSocketService.sendMessage(roomLeaveJson);
    }

    // Dispose of WebSocket invitation stream
    _webSocketService.disposeInvitationStream();

    // Reset game state
    gameProvider.resetGame(newGame: true);
  }

  // String _getPlayerName({required bool isWhite}) {
  //   if (gameProvider.computerMode) {
  //     return isWhite ? 'You' : 'Computer';
  //   } else if (gameProvider.friendsMode && gameProvider.gameModel != null) {
  //     return isWhite
  //         ? (gameProvider.playerColor == PlayerColor.white
  //             ? gameProvider.user.userName
  //             : gameProvider.opponentUsername)
  //         : (gameProvider.playerColor == PlayerColor.white
  //             ? gameProvider.opponentUsername
  //             : gameProvider.user.userName);

  //   }
  //   return isWhite ? 'Player 1' : 'Player 2';
  // }
  String _getPlayerName({required bool isWhite}) {
    if (gameProvider.computerMode) {
      return isWhite ? 'You' : 'Computer';
    } else if (gameProvider.friendsMode && gameProvider.gameModel != null) {
      return isWhite
          ? gameProvider.gameModel!.opponentUsername
          : gameProvider.user.userName;
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
  void dispose() {
    _chessTimer.stop();
    _chessTimer.dispose();
    _timer?.cancel();
    if (stockfish != null) {
      stockfish!.stdin = StockfishUicCommand.stop;
    }

    if (gameProvider.friendsMode) {
      gameProvider.setGameModel();
      gameProvider.setCurrentInvitation();
      // gameProvider.setIsFlipBoard(value: false);
      // gameProvider.setFriendsMode(value: false);
    }
    _webSocketService.disposeInvitationStream();
    _stockfishSubscription?.cancel();
    gameProvider.resetGame(newGame: true);

    super.dispose();
  }
}
