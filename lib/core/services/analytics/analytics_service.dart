import 'package:firebase_analytics/firebase_analytics.dart';

import '../logging/log_redaction.dart';

/// Analytics service for tracking user behavior and app usage.
///
/// Wraps Firebase Analytics with app-specific events and
/// provides a clean interface for the rest of the app.
class AnalyticsService {
  final FirebaseAnalytics _analytics;

  AnalyticsService({FirebaseAnalytics? analytics})
      : _analytics = analytics ?? FirebaseAnalytics.instance;

  /// Get observer for GoRouter navigation tracking.
  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  // ==================== USER IDENTITY ====================

  /// Set user ID for analytics (call on login).
  Future<void> setUserId(String? userId) async {
    await _analytics.setUserId(id: userId);
  }

  /// Set a user property.
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    await _analytics.setUserProperty(name: name, value: value);
  }

  // ==================== SCREEN TRACKING ====================

  /// Log screen view.
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
  }

  // ==================== AUTH EVENTS ====================

  /// Log sign up event.
  Future<void> logSignUp({required String method}) async {
    await _analytics.logSignUp(signUpMethod: method);
  }

  /// Log login event.
  Future<void> logLogin({required String method}) async {
    await _analytics.logLogin(loginMethod: method);
  }

  /// Log logout event.
  Future<void> logLogout() async {
    await _analytics.logEvent(name: 'logout');
    await setUserId(null);
  }

  // ==================== CONNECTION EVENTS ====================

  /// Log when user sends a connection request.
  Future<void> logConnectionRequested({
    required String targetUserId,
    String? source,
  }) async {
    await logEvent(
      name: AnalyticsEvents.connectionRequested,
      parameters: {
        'target_user_id': targetUserId,
        'source': source ?? 'unknown',
      },
    );
  }

  /// Log when user accepts a connection request.
  Future<void> logConnectionAccepted({required String fromUserId}) async {
    await logEvent(
      name: AnalyticsEvents.connectionAccepted,
      parameters: {'from_user_id': fromUserId},
    );
  }

  /// Log when user rejects a connection request.
  Future<void> logConnectionRejected({required String fromUserId}) async {
    await logEvent(
      name: AnalyticsEvents.connectionRejected,
      parameters: {'from_user_id': fromUserId},
    );
  }

  /// Log when user removes a connection.
  Future<void> logConnectionRemoved({required String userId}) async {
    await logEvent(
      name: AnalyticsEvents.connectionRemoved,
      parameters: {'user_id': userId},
    );
  }

  // ==================== CHAT EVENTS ====================

  /// Log message sent.
  Future<void> logMessageSent({
    required String conversationId,
    int? messageLength,
  }) async {
    await logEvent(
      name: AnalyticsEvents.messageSent,
      parameters: {
        'conversation_id': conversationId,
        if (messageLength != null) 'message_length': messageLength,
      },
    );
  }

  /// Log conversation started.
  Future<void> logConversationStarted({required String withUserId}) async {
    await logEvent(
      name: AnalyticsEvents.conversationStarted,
      parameters: {'with_user_id': withUserId},
    );
  }

  // ==================== PROXIMITY EVENTS ====================

  /// Log when proximity scanning starts.
  Future<void> logProximityStarted() async {
    await _analytics.logEvent(name: AnalyticsEvents.proximityStarted);
  }

  /// Log when proximity scanning stops.
  Future<void> logProximityStopped({Duration? duration}) async {
    await logEvent(
      name: AnalyticsEvents.proximityStopped,
      parameters: {
        if (duration != null) 'duration_seconds': duration.inSeconds,
      },
    );
  }

  /// Log when a nearby user is detected.
  Future<void> logNearbyUserDetected({required int count}) async {
    await logEvent(
      name: AnalyticsEvents.nearbyUserDetected,
      parameters: {'count': count},
    );
  }

  /// Log when user views a nearby user's profile.
  Future<void> logNearbyUserViewed({required String userId}) async {
    await logEvent(
      name: AnalyticsEvents.nearbyUserViewed,
      parameters: {'user_id': userId},
    );
  }

  // ==================== PROFILE EVENTS ====================

  /// Log profile update.
  Future<void> logProfileUpdated({List<String>? fieldsUpdated}) async {
    await logEvent(
      name: AnalyticsEvents.profileUpdated,
      parameters: {
        if (fieldsUpdated != null) 'fields': fieldsUpdated.join(','),
      },
    );
  }

  /// Log profile photo changed.
  Future<void> logProfilePhotoChanged({required String source}) async {
    await logEvent(
      name: AnalyticsEvents.profilePhotoChanged,
      parameters: {'source': source}, // 'camera' or 'gallery'
    );
  }

  // ==================== ERROR EVENTS ====================

  /// Log an error event (non-crash).
  Future<void> logError({
    required String errorType,
    String? errorMessage,
    String? screen,
  }) async {
    await logEvent(
      name: AnalyticsEvents.errorOccurred,
      parameters: {
        'error_type': errorType,
        if (errorMessage != null) 'error_message': errorMessage,
        if (screen != null) 'screen': screen,
      },
    );
  }

  // ==================== GENERIC EVENT ====================

  /// Log a custom event.
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    final safe = _sanitizeParameters(parameters);
    await _analytics.logEvent(name: name, parameters: safe);
  }

  Map<String, Object>? _sanitizeParameters(Map<String, Object>? parameters) {
    if (parameters == null || parameters.isEmpty) return parameters;

    // Firebase Analytics requires primitive values (String/num/bool).
    final out = <String, Object>{};

    for (final entry in parameters.entries) {
      final key = entry.key;

      // Hard block known-sensitive keys.
      if (LogRedaction.isSensitiveKey(key)) continue;

      final value = entry.value;
      if (value is String) {
        out[key] = LogRedaction.redactString(value);
      } else if (value is num || value is bool) {
        out[key] = value;
      } else {
        // Best-effort stringify, then redact.
        out[key] = LogRedaction.redactString(value.toString());
      }
    }

    return out.isEmpty ? null : out;
  }
}

/// Analytics event name constants.
abstract class AnalyticsEvents {
  // Auth
  static const String logout = 'logout';

  // Connections
  static const String connectionRequested = 'connection_requested';
  static const String connectionAccepted = 'connection_accepted';
  static const String connectionRejected = 'connection_rejected';
  static const String connectionRemoved = 'connection_removed';

  // Chat
  static const String messageSent = 'message_sent';
  static const String conversationStarted = 'conversation_started';

  // Proximity
  static const String proximityStarted = 'proximity_started';
  static const String proximityStopped = 'proximity_stopped';
  static const String nearbyUserDetected = 'nearby_user_detected';
  static const String nearbyUserViewed = 'nearby_user_viewed';

  // Profile
  static const String profileUpdated = 'profile_updated';
  static const String profilePhotoChanged = 'profile_photo_changed';

  // Errors
  static const String errorOccurred = 'error_occurred';

  // Bluetooth
  static const String bluetoothEnabled = 'bluetooth_enabled';
  static const String bluetoothDisabled = 'bluetooth_disabled';
  static const String bluetoothPermissionDenied = 'bluetooth_permission_denied';
}
