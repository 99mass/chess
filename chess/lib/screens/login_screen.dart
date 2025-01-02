import 'package:chess/constant/constants.dart';
import 'package:chess/model/friend_model.dart';
import 'package:chess/provider/game_provider.dart';
import 'package:chess/screens/main_menu_screen.dart';
import 'package:chess/services/user_service.dart';
import 'package:chess/utils/custom_page_route.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:chess/widgets/custom_image_spinner.dart';
import 'package:chess/widgets/custom_snack_bar.dart';
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
    showCustomSnackBarTop(context, message);
  }

  String? _validateInputs() {
    if (userName.text.isEmpty) {
      return 'Veuillez entrer votre nom d\'utilisateur';
    }
    if (userName.text.length > 10 || userName.text.length < 3) {
      return 'Le nom d\'utilisateur doit avoir entre 3 et 10 caract res';
    }
    if (userName.text.contains(RegExp(r'[^\x00-\x7F]'))) {
      return 'Le nom d\'utilisateur ne peut pas contenir d\'emoji';
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
          CustomPageRoute(child: const MainMenuScreen()),
        );
      } on AuthException catch (e) {
        String message;
        if (e.statusCode == 409) {
          message = 'L\'utilisateur à déja  une session active';
        } else if (e.statusCode == 400) {
          message = 'Format du nom d\'utilisateur ou du mot de passe invalide';
        } else {
          message = 'Échec de l\'authentification : ${e.message}';
        }
        _showError(message);
      }
    } catch (e) {
      print('Connection error: $e');
      _showError(
          'Impossible de se connecter, vérifiez votre connexion internet.');
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
          color: ColorsConstants.colorBg,
        ),
        child: Center(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  child: Image(
                    image: AssetImage('assets/chess_logo.png'),
                    width: 80.0,
                    height: 80.0,
                  ),
                ),
                const SizedBox(height: 50.0),
                SizedBox(
                  width: 300,
                  height: 55,
                  child: CustomTextField(
                    controller: userName,
                    hintText: 'Nom de l\'utilisateur',
                  ),
                ),
                const SizedBox(height: 25.0),
                SizedBox(
                  width: 300,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColorsConstants.colorGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      elevation: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Se connecter',
                          style: TextStyle(
                            fontSize: 20.0,
                            color: ColorsConstants.white,
                          ),
                        ),
                        if (_isLoading) const SizedBox(width: 8),
                        if (_isLoading)
                          const CustomImageSpinner(
                            size: 30.0,
                            duration: Duration(milliseconds: 2000),
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
