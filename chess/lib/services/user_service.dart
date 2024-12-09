import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:chess/model/friend_model.dart';
import 'package:chess/utils/api_link.dart';

class UserService {
  /// Retrieves a user by their username
  /// Returns null if the user does not exist
  static Future<UserProfile?> getUserByUsername(String username) async {
    try {
      final response =
          await http.get(Uri.parse('${apiLink}get?username=$username'));

      if (response.statusCode == 200) {
        return UserProfile.fromJson(json.decode(response.body));
      }

      return null;
    } catch (e) {
      print('Error fetching user: $e');
      return null;
    }
  }

  /// Creates a new user
  /// Returns the created user profile or null in case of an error
  static Future<UserProfile?> createUser(String username) async {
    try {
      final createResponse = await http.post(Uri.parse('${apiLink}create'),
          body: json.encode({'username': username}),
          headers: {'Content-Type': 'application/json'});

      if (createResponse.statusCode == 200) {
        return UserProfile.fromJson(json.decode(createResponse.body));
      }

      return null;
    } catch (e) {
      print('Error creating user: $e');
      return null;
    }
  }

  /// Met à jour le statut en ligne d'un utilisateur
static Future<bool> updateUserOnlineStatus(String username, bool isOnline) async {
  try {
    final response = await http.post(
      Uri.parse('${apiLink}users/online'), 
      body: json.encode({
        'username': username,
        'is_online': isOnline
      }),
      headers: {'Content-Type': 'application/json'}
    );

    return response.statusCode == 200;
  } catch (e) {
    print('Error updating online status: $e');
    return false;
  }
}
}
