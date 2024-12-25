import 'package:squares/squares.dart';

class GameModel {
  String gameId;
  String gameCreatorUid;
  String userId;
  String opponentUsername;
  String positonFen;
  String winnerId;
  String whitesTime;
  String blacksTime;
  bool isWhitesTurn;
  bool isGameOver;
  List<Move> moves;

  GameModel({
    required this.gameId,
    required this.gameCreatorUid,
    required this.userId,
    required this.opponentUsername,
    required this.positonFen,
    required this.winnerId,
    required this.whitesTime,
    required this.blacksTime,
    required this.isWhitesTurn,
    required this.isGameOver,
    required this.moves,
  });

  factory GameModel.fromJson(Map<String, dynamic> json) {
    return GameModel(
      gameId: json['gameId'] ?? '',
      gameCreatorUid: json['gameCreatorUid'] ?? '',
      userId: json['userId'] ?? '',
      opponentUsername: json['opponentUsername'] ?? '',
      positonFen: json['positonFen'] ??
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      winnerId: json['winnerId'] ?? '',
      whitesTime: json['whitesTime'] ?? ' 0',
      blacksTime: json['blacksTime'] ?? '0',
      isWhitesTurn: json['isWhitesTurn'] ?? true,
      isGameOver: json['isGameOver'] ?? false,
      // squareState: json['squareState'] ?? 0,
      moves: (json['moves'] as List?)
              ?.map((move) => Move(from: move['from'], to: move['to']))
              .toList() ??
          [],
    );
  }
}
