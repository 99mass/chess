import 'package:chess/model/friend_model.dart';
import 'package:flutter/material.dart';
import 'package:chess/screens/waiting_room_screen.dart';

class FriendListScreen extends StatefulWidget {
  const FriendListScreen({Key? key}) : super(key: key);

  @override
  State<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen> {
  // Exemple de liste d'amis (à remplacer par votre logique de gestion des amis)
  final List<FriendModel> friendModels = [
    const FriendModel(id: '1', userName: 'KnightMaster'),
    const FriendModel(id: '2', userName: 'QueenSlayer'),
    const FriendModel(id: '3', userName: 'BishopWizard'),
    const FriendModel(id: '4', userName: 'RookDefender'),
    const FriendModel(id: '5', userName: 'PawnPusher'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: const Text(
          'Friend List',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 24,
          ),
        ),
        backgroundColor: Colors.amber[700],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: friendModels.length,
        itemBuilder: (context, index) {
          return _buildFriendItem(friendModels[index]);
        },
      ),
    );
  }

  Widget _buildFriendItem(FriendModel friend) {
    return SingleChildScrollView(
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WaitingRoomScreen(friendId: int.parse(friend.id)),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            border: Border.all(color: Colors.amber[700]!, width: 1),
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  image: DecorationImage(
                    image: AssetImage('assets/avatar.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        alignment: Alignment.center,
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.green[700],
                          shape: BoxShape.circle,
                          border:
                              Border.all(width: 2, color: Colors.green[700]!),
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      friend.userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
