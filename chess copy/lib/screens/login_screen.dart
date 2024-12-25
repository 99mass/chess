import 'package:chess/model/friend_model.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/services/user_service.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:chess/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final userName = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade400,
      ),
    );
  }

  String? _validateInputs() {
    if (userName.text.isEmpty) {
      return 'Please enter your username';
    }
    if (userName.text.length > 10 || userName.text.length < 3) {
      return 'Username must be between 3 and 10 characters';
    }
    if (userName.text.contains(RegExp(r'[^\x00-\x7F]'))) {
      return 'Username cannot contain emojis';
    }
    return null;
  }


  Future<void> _login() async {
    final errorMessage = _validateInputs();
    if (errorMessage != null) {
      _showError(errorMessage);
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      UserProfile? user = await UserService.getUserByUsername(userName.text);

      try {
        user = await UserService.createUser(userName.text);

        await SharedPreferencesStorage.instance.saveUserLocally(user);
        Provider.of<GameProvider>(context, listen: false).setUser(user);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainMenuScreen()),
        );
      } on AuthException catch (e) {
        String message;
        if (e.statusCode == 409) {
          message = 'User already has an active session';
        } else if (e.statusCode == 400) {
          message = 'Invalid username or password format';
        } else {
          message = 'Authentication failed: ${e.message}';
        }
        _showError(message);
      }
    } catch (e) {
      print('Connection error: $e');
      _showError('Unable to connect, check your network.');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/login_bg.jpg'),
            fit: BoxFit.cover,
          ),
          color: Colors.black,
        ),
        child: Center(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: CustomTextField(
                    controller: userName,
                    hintText: 'Enter your username',
                  ),
                ),
                const SizedBox(height: 16.0),
                SizedBox(
                  width: 300,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      shadowColor: Colors.black.withOpacity(0.3),
                      elevation: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Get Started',
                          style: TextStyle(
                            fontSize: 20.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (_isLoading) const SizedBox(width: 8),
                        if (_isLoading)
                          const CircularProgressIndicator(
                            color: Colors.black87,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
