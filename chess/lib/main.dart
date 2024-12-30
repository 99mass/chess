import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/login_screen.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() async { 
  WidgetsFlutterBinding.ensureInitialized();
  final user = await SharedPreferencesStorage.instance.getUserLocally();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => GameProvider()..loadUser(),
        ),
      ],
      child: MyApp(
          initialScreen: user == null || user.userName == "" || user.id == ""
              ? const LoginScreen()
              : const MainMenuScreen()),
    ),
  );
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;

  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Chess',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: initialScreen);
  }
}
