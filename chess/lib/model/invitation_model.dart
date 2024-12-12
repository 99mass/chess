
// Modèle d'invitation à ajouter à votre model/friend_model.dart
class InvitationMessage {
  final String type;
  final String fromUserId;
  final String fromUsername;
  final String toUserId;
  final String toUsername;
  final String? roomId;
  final int timestamp;

  InvitationMessage({
    required this.type,
    required this.fromUserId,
    required this.fromUsername,
    required this.toUserId,
    required this.toUsername,
    this.roomId,
    required this.timestamp,
  });

  // Méthode pour convertir en JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'from_user_id': fromUserId,
      'from_username': fromUsername,
      'to_user_id': toUserId,
      'to_username': toUsername,
      'room_id': roomId,
      'timestamp': timestamp,
    };
  }

  // Méthode de factory pour créer à partir de JSON
  factory InvitationMessage.fromJson(Map<String, dynamic> json) {
    return InvitationMessage(
      type: json['type'],
      fromUserId: json['from_user_id'],
      fromUsername: json['from_username'],
      toUserId: json['to_user_id'],
      toUsername: json['to_username'],
      roomId: json['room_id'],
      timestamp: json['timestamp'],
    );
  }
}