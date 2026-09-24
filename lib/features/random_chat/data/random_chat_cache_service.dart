import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/entities/random_chat_connection.dart';
import '../domain/entities/random_chat_request.dart';
import '../domain/entities/random_chat_user.dart';

/// Persistent cache service for Random Chat data using Hive.
/// 
/// Stores daily suggestions, requests, and connections so users
/// see their data immediately when reopening the app, without
/// showing a loading state.
class RandomChatCacheService {
  static const String _boxName = 'random_chat_cache';
  static const String _suggestionsKey = 'suggestions';
  static const String _incomingRequestsKey = 'incoming_requests';
  static const String _sentRequestsKey = 'sent_requests';
  static const String _activeConnectionKey = 'active_connection';
  static const String _dateKeyKey = 'date_key';
  static const String _userIdKey = 'user_id';
  static const String _lastUpdatedKey = 'last_updated';

  final Logger _logger;
  Box? _box;

  RandomChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Initialize the cache (must be called before use).
  Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox(_boxName);
      } else {
        _box = Hive.box(_boxName);
      }
      _logger.d('Random Chat cache initialized');
    } catch (e, stack) {
      _logger.e('Failed to initialize Random Chat cache', error: e, stackTrace: stack);
      // Recover from PathNotFoundException or corrupted box files:
      // Ensure the Hive directory exists, delete the corrupt box, and retry once.
      try {
        await _ensureHiveDirectoryExists();
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox(_boxName);
        _logger.i('Random Chat cache recovered after error');
      } catch (retryError) {
        _logger.e('Recovery also failed, cache will be unavailable', error: retryError);
        _box = null;
      }
    }
  }

  /// Ensures the Hive storage directory exists on disk.
  /// Fixes PathNotFoundException on devices where the directory was deleted
  /// (e.g., by clearAllAppData or OS storage cleanup).
  Future<void> _ensureHiveDirectoryExists() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (!appDir.existsSync()) {
        appDir.createSync(recursive: true);
      }
    } catch (_) {
      // Best-effort: if we can't create the directory, the retry will fail
      // and we'll fall back to null _box.
    }
  }

  /// Safely access the box, returning null if it's been closed or invalidated.
  Box? get _safeBox {
    try {
      if (_box != null && _box!.isOpen) return _box;
    } catch (_) {}
    _box = null;
    return null;
  }

  /// Get cached data for today.
  /// Returns null if no cache or cache is from a different day/user.
  Future<RandomChatCacheData?> getCachedData({
    required String userId,
    required String dateKey,
  }) async {
    try {
      if (_safeBox == null) await init();
      if (_safeBox == null) return null;

      final cachedUserId = _box!.get(_userIdKey);
      final cachedDateKey = _box!.get(_dateKeyKey);

      // Cache is invalid if it's for a different user or date
      if (cachedUserId != userId || cachedDateKey != dateKey) {
        _logger.d('Cache miss: userId=$cachedUserId vs $userId, dateKey=$cachedDateKey vs $dateKey');
        return null;
      }

      final suggestionsJson = _box!.get(_suggestionsKey) as String?;
      final incomingJson = _box!.get(_incomingRequestsKey) as String?;
      final sentJson = _box!.get(_sentRequestsKey) as String?;
      final connectionJson = _box!.get(_activeConnectionKey) as String?;
      final lastUpdated = _box!.get(_lastUpdatedKey) as int?;

      if (suggestionsJson == null) {
        _logger.d('Cache miss: no suggestions data');
        return null;
      }

      final suggestions = _decodeSuggestions(suggestionsJson);
      final incomingRequests = _decodeRequests(incomingJson ?? '[]');
      final sentRequests = _decodeRequests(sentJson ?? '[]');
      final activeConnection = _decodeConnection(connectionJson);

      _logger.d('Cache hit: ${suggestions.length} suggestions, '
          '${incomingRequests.length} incoming, ${sentRequests.length} sent');

      return RandomChatCacheData(
        suggestions: suggestions,
        incomingRequests: incomingRequests,
        sentRequests: sentRequests,
        activeConnection: activeConnection,
        dateKey: dateKey,
        userId: userId,
        lastUpdated: lastUpdated != null 
            ? DateTime.fromMillisecondsSinceEpoch(lastUpdated)
            : DateTime.now(),
      );
    } catch (e, stack) {
      _logger.e('Error reading cache', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Save complete state to cache.
  Future<void> saveCache({
    required String userId,
    required String dateKey,
    required List<RandomChatUser> suggestions,
    required List<RandomChatRequest> incomingRequests,
    required List<RandomChatRequest> sentRequests,
    RandomChatConnection? activeConnection,
  }) async {
    try {
      if (_safeBox == null) await init();
      if (_safeBox == null) return;

      await _box!.put(_userIdKey, userId);
      await _box!.put(_dateKeyKey, dateKey);
      await _box!.put(_suggestionsKey, _encodeSuggestions(suggestions));
      await _box!.put(_incomingRequestsKey, _encodeRequests(incomingRequests));
      await _box!.put(_sentRequestsKey, _encodeRequests(sentRequests));
      await _box!.put(
        _activeConnectionKey,
        activeConnection != null ? _encodeConnection(activeConnection) : null,
      );
      await _box!.put(_lastUpdatedKey, DateTime.now().millisecondsSinceEpoch);

      _logger.d('Cache updated: ${suggestions.length} suggestions, '
          '${incomingRequests.length} incoming, ${sentRequests.length} sent');
    } catch (e, stack) {
      _logger.e('Error saving cache', error: e, stackTrace: stack);
    }
  }

  /// Update only incoming requests in cache.
  Future<void> updateIncomingRequests(List<RandomChatRequest> requests) async {
    try {
      if (_safeBox == null) return;
      await _box!.put(_incomingRequestsKey, _encodeRequests(requests));
      await _box!.put(_lastUpdatedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      _logger.w('Error updating incoming requests in cache', error: e);
    }
  }

  /// Update only sent requests in cache.
  Future<void> updateSentRequests(List<RandomChatRequest> requests) async {
    try {
      if (_safeBox == null) return;
      await _box!.put(_sentRequestsKey, _encodeRequests(requests));
      await _box!.put(_lastUpdatedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      _logger.w('Error updating sent requests in cache', error: e);
    }
  }

  /// Update only active connection in cache.
  Future<void> updateActiveConnection(RandomChatConnection? connection) async {
    try {
      if (_safeBox == null) return;
      await _box!.put(
        _activeConnectionKey,
        connection != null ? _encodeConnection(connection) : null,
      );
      await _box!.put(_lastUpdatedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      _logger.w('Error updating active connection in cache', error: e);
    }
  }

  /// Clear all cached data (e.g., on logout or date change).
  Future<void> clearCache() async {
    try {
      if (_safeBox == null) return;
      await _box!.clear();
      _logger.d('Cache cleared');
    } catch (e) {
      _logger.w('Error clearing cache', error: e);
    }
  }

  /// Close the cache box.
  Future<void> close() async {
    try {
      await _box?.close();
      _box = null;
    } catch (e) {
      _logger.w('Error closing cache', error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // Encoding/Decoding helpers
  // ---------------------------------------------------------------------------

  String _encodeSuggestions(List<RandomChatUser> suggestions) {
    return jsonEncode(suggestions.map((s) => s.toJson()).toList());
  }

  List<RandomChatUser> _decodeSuggestions(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((item) => RandomChatUser.fromJson(item as Map<String, dynamic>)).toList();
  }

  String _encodeRequests(List<RandomChatRequest> requests) {
    return jsonEncode(requests.map((r) => r.toJson()).toList());
  }

  List<RandomChatRequest> _decodeRequests(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((item) => RandomChatRequest.fromJson(item as Map<String, dynamic>)).toList();
  }

  String? _encodeConnection(RandomChatConnection connection) {
    return jsonEncode(connection.toJson());
  }

  RandomChatConnection? _decodeConnection(String? json) {
    if (json == null || json.isEmpty) return null;
    return RandomChatConnection.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }
}

/// Data class for cached random chat state.
class RandomChatCacheData {
  final List<RandomChatUser> suggestions;
  final List<RandomChatRequest> incomingRequests;
  final List<RandomChatRequest> sentRequests;
  final RandomChatConnection? activeConnection;
  final String dateKey;
  final String userId;
  final DateTime lastUpdated;

  const RandomChatCacheData({
    required this.suggestions,
    required this.incomingRequests,
    required this.sentRequests,
    this.activeConnection,
    required this.dateKey,
    required this.userId,
    required this.lastUpdated,
  });
}
