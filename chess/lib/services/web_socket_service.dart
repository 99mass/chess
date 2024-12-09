import 'dart:async';
import 'dart:convert';
import 'package:chess/utils/api_link.dart';
import 'package:chess/utils/shared_preferences_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chess/services/user_service.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  StreamController<List<String>> _onlineUsersController =
      StreamController<List<String>>.broadcast();
  Timer? _reconnectTimer;
  bool _isConnected = false;

  Stream<List<String>> get onlineUsersStream => _onlineUsersController.stream;
  bool get isConnected => _isConnected;

  Future<void> connectWebSocket() async {
    // Récupérer l'utilisateur depuis SharedPreferences
    final user = await SharedPreferencesStorage.instance.getUserLocally();

    if (user == null || user.userName.isEmpty) {
      print('Pas d\'utilisateur connecté');
      return;
    }

    // URL de votre WebSocket
    final wsUrl = '$socketLink?username=${user.userName}';

    try {
      // Établir la connexion WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Mettre à jour le statut en ligne côté serveur
      await UserService.updateUserOnlineStatus(user.userName, true);

      // Écouter les messages
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: _onConnectionClosed,
        onError: (error) {
          print('WebSocket error: $error');
          _reconnect();
        },
      );

      _isConnected = true;
      print('WebSocket connecté pour ${user.userName}');
    } catch (e) {
      print('Erreur de connexion WebSocket: $e');
      _reconnect();
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final Map<String, dynamic> data = json.decode(message);

      if (data['type'] == 'online_users') {
        final List<String> onlineUsers =
            List<String>.from(json.decode(data['content']));
        print('Liste des utilisateurs en ligne: ${onlineUsers.join(', ')}');
        _onlineUsersController.add(onlineUsers);
      }
    } catch (e) {
      print('Erreur de traitement du message: $e');
    }
  }

  void _onConnectionClosed() {
    print('WebSocket déconnecté');
    _isConnected = false;
    _reconnect();
  }

  void _reconnect() {
    // Annuler le timer précédent s'il existe
    _reconnectTimer?.cancel();

    // Tenter de se reconnecter toutes les 5 secondes
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected) {
        print('Tentative de reconnexion...');
        await connectWebSocket();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> disconnect() async {
    // Récupérer l'utilisateur depuis SharedPreferences
    final user = await SharedPreferencesStorage.instance.getUserLocally();

    if (user != null && user.userName.isNotEmpty) {
      // Mettre à jour le statut hors ligne côté serveur
      await UserService.updateUserOnlineStatus(user.userName, false);
    }

    // Fermer la connexion WebSocket
    _channel?.sink.close();
    _isConnected = false;

    // Fermer le stream des utilisateurs en ligne
    await _onlineUsersController.close();

    _onlineUsersController = StreamController<List<String>>.broadcast();
  }

  // Méthode pour envoyer un message via WebSocket
  void sendMessage(String message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(message);
    }
  }
}
