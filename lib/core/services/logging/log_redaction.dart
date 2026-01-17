import 'package:flutter/foundation.dart';

/// Centralized redaction/sanitization for logs/telemetry.
///
/// Default behavior:
/// - Always redact sensitive BLE identifiers/payloads from on-device logs.
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
    if (normalized.contains('manufacturer')) return true;
    if (normalized.contains('payload')) return true;
    if (normalized.contains('mac')) return true;
    if (normalized.contains('address')) return true;

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
    r'(anonymousId|bleId|bleAnonymousId|currentAnonymousId|manufacturerData|manufacturerPayload|macAddress|bluetoothAddress|deviceAddress)\s*[:=]\s*([^\s,;\]\}\)]+)',
    caseSensitive: false,
  );

  static final RegExp _jsonRedactionPattern = RegExp(
    r'("(anonymousId|bleId|bleAnonymousId|currentAnonymousId|manufacturerData|manufacturerPayload|macAddress|bluetoothAddress|deviceAddress)"\s*:\s*)"[^"]*"',
    caseSensitive: false,
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
