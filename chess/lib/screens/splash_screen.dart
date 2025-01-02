import 'package:chess/constant/constants.dart';
import 'package:chess/screens/login_screen.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/utils/custom_page_route.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkUserAndNavigate();
  }

  Future<void> _checkUserAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final user = await SharedPreferencesStorage.instance.getUserLocally();
    final nextPage = user == null || user.userName.isEmpty || user.id.isEmpty
        ? const LoginScreen()
        : const MainMenuScreen();
    Navigator.pushReplacement(context, CustomPageRoute2(child: nextPage));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ColorsConstants.colorBg,
      body: Center(
        child: SizedBox(
          child: Image(
            image: AssetImage('assets/chess_logo.png'),
            width: 100.0,
            height: 100.0,
          ),
        ),
      ),
    );
  }
}
