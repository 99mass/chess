import 'package:stockfish/stockfish.dart';

class StockfishUicCommand {
  static const String uci = 'uci';
  static const String isReady = 'isready';
  static const String uciNewGame = 'ucinewgame';
  static const String goMoveTime = 'go movetime';
  static const String goInfinite = 'go infinite';
  static const String stop = 'stop';
  static const String position = 'position fen';
  static const String bestMove = 'bestmove';
  static const String setOption = 'setoption name';
}

class StockfishInstance {
  static final Stockfish _instance = Stockfish();

  static Stockfish get instance => _instance;

  StockfishInstance._(); // Constructeur privé pour éviter l'instanciation
}
