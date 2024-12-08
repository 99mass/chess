class FriendModel {
  final String id;
  final String userName;
  final String? roomId;
  final String? color;
  final bool isReady;
  final ConnectionStatus connectionStatus;

  const FriendModel({
    required this.id,
    required this.userName,
    this.roomId,
    this.color,
    this.isReady = false,
    this.connectionStatus = ConnectionStatus.disconnected,
  });
}

enum ConnectionStatus {
  disconnected,
  connected,
  inGame,
}


class UserProfile {
  final String id;
  final String userName;

  UserProfile({required this.id, required this.userName});

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      userName: json['username'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': userName,
  };


   Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': userName,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'],
      userName: map['username'],
    );
  }
}