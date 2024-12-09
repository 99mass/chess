import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:chess/model/friend_model.dart';

class SharedPreferencesStorage {
  SharedPreferencesStorage._privateConstructor();
  static final SharedPreferencesStorage instance =
      SharedPreferencesStorage._privateConstructor();

  static const String _userKey = 'user_profile';

  /// Save user locally using SharedPreferences
  Future<void> saveUserLocally(UserProfile user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
  
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    } catch (e) {
      print('Error saving user: $e');
    }
  }

  /// Retrieve user information locally
  Future<UserProfile?> getUserLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userString = prefs.getString(_userKey);

      if (userString != null) {
        final Map<String, dynamic> userMap = jsonDecode(userString);
        return UserProfile.fromJson(userMap);
      }
    } catch (e) {
      print('Error retrieving user: $e');
    }
    return null;
  }

  /// Delete user information locally
  Future<void> deleteUserLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
    } catch (e) {
      print('Error deleting user: $e');
    }
  }
}
