import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart' hide Logger;
import 'package:injectable/injectable.dart';

@lazySingleton
class StreamTokenService {
  final Logger _logger;
  
  // TODO: Replace with your actual backend URL
  // If running on Android emulator, use 10.0.2.2 instead of localhost
  final String _backendUrl = 'http://10.0.2.2:3000/api/getStreamToken';

  StreamTokenService({required Logger logger}) : _logger = logger;

  /// Fetches a Stream Chat token for the currently authenticated Firebase user
  Future<String?> fetchToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e('Cannot fetch Stream token: No Firebase user logged in.');
      return null;
    }

    try {
      final idToken = await user.getIdToken();
      if (idToken == null) {
        _logger.e('Failed to get Firebase ID token.');
        return null;
      }

      final response = await http.post(
        Uri.parse(_backendUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'data': {} // The backend expects a data object for onCall functions
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final token = body['data']?['token'] as String?;
        if (token != null) {
          _logger.i('Successfully fetched Stream token.');
          return token;
        } else {
          _logger.e('Stream token not found in response: $body');
          return null;
        }
      } else {
        _logger.e('Failed to fetch Stream token. Status: ${response.statusCode}, Body: ${response.body}');
        return null;
      }
    } catch (e) {
      _logger.e('Error fetching Stream token:', error: e);
      return null;
    }
  }

  /// Connects the Stream Chat client for the current user
  Future<void> connectUser(StreamChatClient client) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Disconnect if already connected
    if (client.wsConnectionStatus == ConnectionStatus.connected) {
      await client.disconnectUser();
    }

    final token = await fetchToken();
    if (token != null) {
      try {
        await client.connectUser(
          User(
            id: user.uid,
            name: user.displayName ?? 'User',
            image: user.photoURL,
          ),
          token,
        );
        _logger.i('Successfully connected to Stream Chat as ${user.uid}');
      } catch (e) {
        _logger.e('Error connecting to Stream Chat:', error: e);
      }
    }
  }
  
  /// Disconnects the user from Stream Chat
  Future<void> disconnectUser(StreamChatClient client) async {
    try {
      await client.disconnectUser();
      _logger.i('Successfully disconnected from Stream Chat.');
    } catch (e) {
      _logger.e('Error disconnecting from Stream Chat:', error: e);
    }
  }
}
