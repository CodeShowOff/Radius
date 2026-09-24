import 'package:flutter/foundation.dart';

/// Centralized redaction/sanitization for logs/telemetry.
///
/// Default behavior:
/// - Always redact sensitive data from on-device logs, including:
///   - BLE identifiers/payloads (device IDs, MAC addresses, manufacturer data)
///   - FCM tokens and push notification tokens
///   - User IDs and account identifiers
///   - Email addresses
///   - GPS coordinates (latitude/longitude)
/// - You can temporarily disable redaction in debug builds only via:
///   `--dart-define=RADIUS_ALLOW_SENSITIVE_LOGS=true`
///
/// Note: never disable redaction in release builds.
class LogRedaction {
  static const bool _allowSensitiveLogs =
      bool.fromEnvironment('RADIUS_ALLOW_SENSITIVE_LOGS', defaultValue: false);

  static bool get _shouldRedact => !(kDebugMode && _allowSensitiveLogs);

  static const Set<String> _sensitiveKeys = <String>{
    // Anonymous IDs / BLE IDs
    'bleid',
    'ble_id',
    'anonymousid',
    'bleanonymousid',
    'currentanonymousid',

    // Device addresses / identifiers
    'address',
    'deviceaddress',
    'bluetoothaddress',
    'macaddress',
    'remoteid',
    'deviceid',

    // Payload bytes
    'manufacturerdata',
    'manufacturerpayload',
    'manufacturerpayloadfull',
    'mfgdata',
    'payload',

    // FCM tokens
    'fcmtoken',
    'fcm_token',
    'fcmtokens',
    'fcm_tokens',
    'messagingtoken',
    'pushtoken',
    'push_token',
    'notificationtoken',

    // User identifiers
    'userid',
    'user_id',
    'uid',
    'user1',
    'user2',
    'userid1',
    'userid2',
    'user_id_1',
    'user_id_2',
    'ownerid',
    'owner_id',
    'creatorid',
    'creator_id',
    'senderid',
    'sender_id',
    'recipientid',
    'recipient_id',
    'seekerid',
    'seeker_id',
    'helperid',
    'helper_id',
    'memberid',
    'member_id',

    // Email addresses
    'email',
    'emailaddress',
    'email_address',
    'useremail',
    'user_email',

    // GPS coordinates
    'latitude',
    'longitude',
    'lat',
    'lng',
    'lon',
    'gps',
    'coordinates',
    'location',
    'geolocation',
    'position',
    'geohash',
    'geo_hash',
  };

  // Keys that are *allowed* to contain derived values (non-reversible tokens)
  // used for lookup, not raw BLE identifiers.
  static const Set<String> _explicitlyAllowedKeys = <String>{
    'bletoken',
    'ble_token',
  };

  static bool isSensitiveKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (_explicitlyAllowedKeys.contains(normalized)) return false;
    if (_sensitiveKeys.contains(normalized)) return true;

    // Heuristic matches (case-insensitive)
    // - any key containing "ble" and "id" (but not token)
    if (normalized.contains('ble') && normalized.contains('id')) {
      return !normalized.contains('token');
    }

    // BLE-related patterns
    if (normalized.contains('manufacturer')) return true;
    if (normalized.contains('payload')) return true;
    if (normalized.contains('mac')) return true;
    if (normalized.contains('address')) return true;

    // FCM/Push token patterns
    if (normalized.contains('fcm')) return true;
    if (normalized.contains('pushtoken')) return true;
    if (normalized.contains('messagingtoken')) return true;

    // User ID patterns
    if (normalized.contains('userid')) return true;
    if (normalized.contains('user_id')) return true;
    if (normalized.endsWith('id') &&
        (normalized.contains('user') ||
            normalized.contains('owner') ||
            normalized.contains('sender') ||
            normalized.contains('recipient') ||
            normalized.contains('seeker') ||
            normalized.contains('helper') ||
            normalized.contains('member') ||
            normalized.contains('creator'))) {
      return true;
    }

    // Email patterns
    if (normalized.contains('email')) return true;

    // GPS coordinate patterns
    if (normalized.contains('latitude')) return true;
    if (normalized.contains('longitude')) return true;
    if (normalized.contains('geohash')) return true;
    if (normalized == 'lat' || normalized == 'lng' || normalized == 'lon') {
      return true;
    }
    if (normalized.contains('gps')) return true;
    if (normalized.contains('coordinates')) return true;
    if (normalized.contains('geolocation')) return true;

    return false;
  }

  static Map<String, Object?>? redactMap(Map<String, Object?>? data) {
    if (!_shouldRedact) return jsonifyMap(data);
    if (data == null || data.isEmpty) return data;

    final out = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key;
      out[key] = redactValue(key, entry.value);
    }
    return out;
  }

  static Object? redactValue(String key, Object? value) {
    if (!_shouldRedact) return jsonify(value);

    if (isSensitiveKey(key)) {
      return _redactedPlaceholder(value);
    }

    if (value is Map) {
      final mapped = <String, Object?>{};
      for (final e in value.entries) {
        mapped[e.key.toString()] = redactValue(e.key.toString(), e.value);
      }
      return mapped;
    }

    if (value is Iterable) {
      return value.map((v) => redactValue(key, v)).toList(growable: false);
    }

    if (value is String) {
      return redactString(value);
    }

    return jsonify(value);
  }

  static final RegExp _kvRedactionPattern = RegExp(
    r'(anonymousId|bleId|bleAnonymousId|currentAnonymousId|manufacturerData|manufacturerPayload|macAddress|bluetoothAddress|deviceAddress|fcmToken|fcm_token|userId|user_id|uid|email|latitude|longitude|lat|lng|geoHash|geo_hash)\s*[:=]\s*([^\s,;\]\}\)]+)',
    caseSensitive: false,
  );

  static final RegExp _jsonRedactionPattern = RegExp(
    r'("(anonymousId|bleId|bleAnonymousId|currentAnonymousId|manufacturerData|manufacturerPayload|macAddress|bluetoothAddress|deviceAddress|fcmToken|fcm_token|userId|user_id|uid|email|latitude|longitude|lat|lng|geoHash|geo_hash)"\s*:\s*)"[^"]*"',
    caseSensitive: false,
  );

  /// Redacts email addresses from strings (e.g., user@example.com -> redacted_email)
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b',
  );

  /// Redacts GPS coordinate pairs (e.g., (37.7749, -122.4194) -> redacted_coords)
  static final RegExp _coordsPattern = RegExp(
    r'\(?\s*-?\d+\.?\d*\s*,\s*-?\d+\.?\d*\s*\)?',
  );

  static String redactString(String input) {
    if (!_shouldRedact) return input;

    var out = input;

    // Redact common key=value patterns.
    out = out.replaceAllMapped(_kvRedactionPattern, (m) {
      return '${m.group(1)}=<redacted>';
    });

    // Redact JSON-ish fields: "key": "value".
    out = out.replaceAllMapped(_jsonRedactionPattern, (m) {
      return '${m.group(1)}"<redacted>"';
    });

    // Redact email addresses
    out = out.replaceAll(_emailPattern, '<redacted_email>');

    // Redact GPS coordinate pairs (but be conservative to avoid over-redaction)
    // Only redact if it looks like GPS coordinates in context
    if (out.contains('lat') ||
        out.contains('long') ||
        out.contains('gps') ||
        out.contains('coord') ||
        out.contains('position') ||
        out.contains('location')) {
      out = out.replaceAll(_coordsPattern, '<redacted_coords>');
    }

    return out;
  }

  static Object? _redactedPlaceholder(Object? value) {
    if (value == null) return '<redacted>';
    if (value is List) return '<redacted ${value.length} items>';
    return '<redacted>';
  }

  /// Converts arbitrary values into JSON-encodable primitives.
  static Object? jsonify(Object? value) {
    if (value == null) return null;
    if (value is num || value is bool || value is String) return value;

    if (value is Map) {
      final mapped = <String, Object?>{};
      for (final e in value.entries) {
        mapped[e.key.toString()] = jsonify(e.value);
      }
      return mapped;
    }

    if (value is Iterable) {
      return value.map(jsonify).toList(growable: false);
    }

    return value.toString();
  }

  static Map<String, Object?>? jsonifyMap(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) return data;
    final out = <String, Object?>{};
    for (final e in data.entries) {
      out[e.key] = jsonify(e.value);
    }
    return out;
  }
}
