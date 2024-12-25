class UserProfile {
  final String id;
  final String userName;
  final bool isOnline;
  final bool isInRoom;

  UserProfile({
    required this.id,
    required this.userName,
    this.isOnline = false,
    this.isInRoom = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
        id: json['id'],
        userName: json['username'],
        isOnline: json['isOnline'] ?? false,
        isInRoom: json['isInRoom'] ?? false);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': userName,
        'isOnline': isOnline,
        'isInRoom': isInRoom,
      };

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': userName,
      'isOnline': isOnline,
      'isInRoom': isInRoom
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
        id: map['id'],
        userName: map['username'],
        isOnline: map['isOnline'] ?? false,
        isInRoom: map['isInRoom'] ?? false);
  }
}
