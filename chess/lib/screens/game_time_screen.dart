import 'package:chess/constant/constants.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/game_board_screen.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class GameTimeScreen extends StatefulWidget {
  const GameTimeScreen({super.key});

  @override
  State<GameTimeScreen> createState() => _GameTimeScreenState();
}

class _GameTimeScreenState extends State<GameTimeScreen> {
  // Définir les options de temps de jeu
  final List<int> timeOptions = [3, 5, 10, 20, 30, 60];
  int selectedTime = 10;

  // Définir les niveaux de difficulté
  final List<GameDifficulty> difficultyLevels = [
    GameDifficulty.easy,
    GameDifficulty.medium,
    GameDifficulty.hard
  ];
  GameDifficulty selectedDifficulty =
      GameDifficulty.medium;

  // Définir les options de couleurs de pions
  final List<PlayerColor> colorOptions = [PlayerColor.white, PlayerColor.black];
  PlayerColor selectedColor = PlayerColor.white;
  bool isLoading = false;

  void _startGame(GameProvider gameProvider) async {
    setState(() {
      isLoading = true;
    });

    gameProvider.setCompturMode(value: true);
    gameProvider.setFriendsMode(value: false);
    gameProvider.setGameDifficulty(gameDifficulty: selectedDifficulty);
    gameProvider.setGameTime(gameTime: selectedTime);
    gameProvider.setPlayerColor(
        player: selectedColor == PlayerColor.white ? 0 : 1);
    // gameProvider.setIsloading( true);
    gameProvider.setIsGameEnd(value: false);

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        isLoading = false;
      });
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const GameBoardScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameProvider = context.read<GameProvider>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: ColorsConstants.colorBg,
        leading: IconButton(
          icon: Image.asset(
            'assets/icons8_arrow_back.png',
            width: 30,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: ColorsConstants.colorBg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(bottom: 20.0),
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/chess_logo.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const Text(
                'Choisir les options',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 30),

              // Sélection de couleur de pions
              Wrap(
                runSpacing: 15,
                children: colorOptions.map((PlayerColor colorP) {
                  return ElevatedButton(
                      onPressed: () {
                        setState(() {
                          selectedColor = colorP;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedColor == colorP
                            ? ColorsConstants.colorGreen
                            : ColorsConstants.colorBg3,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(150, 80),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(color: ColorsConstants.white),
                          borderRadius: BorderRadius.only(
                            topLeft: colorP == PlayerColor.white
                                ? const Radius.circular(10)
                                : const Radius.circular(0),
                            bottomLeft: colorP == PlayerColor.white
                                ? const Radius.circular(10)
                                : const Radius.circular(0),
                            topRight: colorP == PlayerColor.black
                                ? const Radius.circular(10)
                                : const Radius.circular(0),
                            bottomRight: colorP == PlayerColor.black
                                ? const Radius.circular(10)
                                : const Radius.circular(0),
                          ),
                        ),
                      ),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image(
                              image: AssetImage(
                                  'assets/${colorP == PlayerColor.white ? 'icons8_white_chess' : 'icons8_black_chess'}.png'),
                              width: 30,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              colorP == PlayerColor.white ? 'Blanc' : 'Noir',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: selectedColor == colorP
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ]));
                }).toList(),
              ),
              const SizedBox(height: 30),

              // Grille de Sélection de difficulté
              Container(
                width: 300,
                height: 70,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: ColorsConstants.colorBg3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ColorsConstants.white,
                    )),
                child: DropdownButton<GameDifficulty>(
                  isExpanded: true,
                  menuWidth: 300,
                  underline: Container(),
                  dropdownColor: ColorsConstants.colorBg3,
                  icon: const Image(
                    image: AssetImage('assets/icons8_arrow_down.png'),
                    width: 30,
                    height: 30,
                  ),
                  value: selectedDifficulty,
                  onChanged: (GameDifficulty? newValue) {
                    setState(() {
                      selectedDifficulty = newValue!;
                    });
                  },
                  items: difficultyLevels.map((difficulty) {
                    return DropdownMenuItem<GameDifficulty>(
                        value: difficulty,
                        child: Row(
                          children: [
                            const Image(
                              image: AssetImage('assets/icons8_level.png'),
                              width: 30,
                              height: 30,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              switch (difficulty) {
                                GameDifficulty.easy => 'Débutant',
                                GameDifficulty.medium => 'Intermédiaire',
                                GameDifficulty.hard => 'Expert',
                              },
                              style: TextStyle(
                                color: ColorsConstants.white,
                                fontSize: 18,
                                fontWeight: selectedDifficulty == difficulty
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ));
                  }).toList(),
                ),
              ),

              const SizedBox(height: 30),

              // Grille de sélection de temps
              Container(
                width: 300,
                height: 70,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: ColorsConstants.colorBg3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ColorsConstants.white,
                    )),
                child: DropdownButton<int>(
                  isExpanded: true,
                  menuWidth: 300,
                  underline: Container(),
                  dropdownColor: ColorsConstants.colorBg3,
                  icon: const Image(
                    image: AssetImage('assets/icons8_arrow_down.png'),
                    width: 30,
                    height: 30,
                  ),
                  value: selectedTime,
                  onChanged: (int? newValue) {
                    setState(() {
                      selectedTime = newValue!;
                    });
                  },
                  items: timeOptions.map((time) {
                    return DropdownMenuItem<int>(
                      value: time,
                      child: Row(
                        children: [
                          const Image(
                            image: AssetImage('assets/icons8_time.png'),
                            width: 30,
                            height: 30,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$time min',
                            style: TextStyle(
                              color: ColorsConstants.white,
                              fontSize: 18,
                              fontWeight: selectedTime == time
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 40),

              ElevatedButton(
                  onPressed: () => _startGame(gameProvider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColorsConstants.colorGreen,
                    foregroundColor: ColorsConstants.white,
                    minimumSize: const Size(300, 60),
                    maximumSize: const Size(300, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 5,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Démarrer le jeu',
                        style: TextStyle(
                          fontSize: 24,
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 10.0,
                        ),
                      if (isLoading)
                        const CustomImageSpinner(
                          size: 30.0,
                          duration: Duration(milliseconds: 20000),
                        ),
                    ],
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
