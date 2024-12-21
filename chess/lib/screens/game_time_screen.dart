import 'package:chess/constant/constants.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/game_board_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GameTimeScreen extends StatefulWidget {
  const GameTimeScreen({super.key});

  @override
  State<GameTimeScreen> createState() => _GameTimeScreenState();
}

class _GameTimeScreenState extends State<GameTimeScreen> {
  // Définir les options de temps de jeu
  final List<int> timeOptions = [1, 5, 10, 20, 30, 60];
  int selectedTime = 10; // Valeur par défaut de 10 minutes

  // Définir les niveaux de difficulté
  final List<GameDifficulty> difficultyLevels = [
    GameDifficulty.easy,
    GameDifficulty.medium,
    GameDifficulty.hard
  ];
  GameDifficulty selectedDifficulty =
      GameDifficulty.medium; // Valeur par défaut

  // Définir les options de couleurs de pions
  final List<PlayerColor> colorOptions = [PlayerColor.white, PlayerColor.black];
  PlayerColor selectedColor = PlayerColor.white; // Valeur par défaut

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();

    return Scaffold(
      backgroundColor: Colors.black54,
      appBar: AppBar(
        title: const Text(
          'Game Time Selection',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.amber[700],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Game Duration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            // Grille de sélection de temps
            Wrap(
              spacing: 15,
              runSpacing: 15,
              children: timeOptions.map((time) {
                return ElevatedButton(
                  onPressed: () {
                    setState(() {
                      selectedTime = time;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedTime == time
                        ? Colors.amber[600]
                        : Colors.grey[800],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(100, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    '$time min',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: selectedTime == time
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 30),

            // Sélection de difficulté uniquement en mode ordinateur
            if (gameProvider.computerMode) ...[
              const Text(
                'Game Difficulty',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 15,
                runSpacing: 15,
                children: difficultyLevels.map((difficulty) {
                  return ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedDifficulty = difficulty;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedDifficulty == difficulty
                          ? Colors.amber[600]
                          : Colors.grey[800],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(100, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      switch (difficulty) {
                        GameDifficulty.easy => 'easy',
                        GameDifficulty.medium => 'medium',
                        GameDifficulty.hard => 'hard',
                      },
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: selectedDifficulty == difficulty
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 30),
            ],

            // Sélection de couleur de pions
            const Text(
              'Player Color',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 15,
              runSpacing: 15,
              children: colorOptions.map((color) {
                return ElevatedButton(
                  onPressed: () {
                    setState(() {
                      selectedColor = color;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedColor == color
                        ? Colors.amber[600]
                        : Colors.grey[800],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(100, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text(
                    switch (color) {
                      PlayerColor.white => 'White',
                      PlayerColor.black => 'Black',
                    },
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: selectedColor == color
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 30),

            // Bouton pour confirmer la sélection
            ElevatedButton(
              onPressed: () {
                gameProvider.setCompturMode(value: true);
                gameProvider.setFriendsMode(value: false);
                gameProvider.setGameDifficulty(
                    gameDifficulty: selectedDifficulty);
                gameProvider.setGameTime(gameTime: selectedTime);
                gameProvider.setPlayerColor(
                    player: selectedColor == PlayerColor.white ? 0 : 1);
                gameProvider.setIsloadind(value: true);
                gameProvider.setIsGameEnd(value: false);

                // Naviguer vers l'écran de jeu avec le temps et la difficulté sélectionnés
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GameBoardScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[600],
                foregroundColor: Colors.black87,
                minimumSize: const Size(250, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
              ),
              child: const Text(
                'Start Game',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
