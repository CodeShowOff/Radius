import 'package:flutter/foundation.dart';

import '../logging/device_log.dart';

/// Build flag to force safe/redacted BLE logging even in non-release builds.
///
/// Usage: `--dart-define=RADIUS_SAFE_BLE_LOGGING=true`
const bool _forceSafeBleLogging =
    bool.fromEnvironment('RADIUS_SAFE_BLE_LOGGING', defaultValue: false);

bool get _shouldRedactSensitive => kReleaseMode || _forceSafeBleLogging;

const Set<String> _sensitiveKeys = {
  // Anonymous IDs
  'anonymousId',
  'bleAnonymousId',
  'currentAnonymousId',
  // Device addresses / identifiers
  'address',
  'deviceAddress',
  'deviceId',
  'remoteId',
  'macAddress',
  // Manufacturer payloads (full bytes)
  'manufacturerData',
  'manufacturerPayload',
  'manufacturerPayloadFull',
  'mfgData',
};

/// BLE-safe debug logging.
///
/// - Debug/profile: logs raw payloads for troubleshooting.
/// - Release (or when `RADIUS_SAFE_BLE_LOGGING=true`): redacts sensitive fields.
void logDebug(String message, [Map<String, Object?>? data]) {
  final normalized = normalizeBleLogData(data);
  final safeData =
      _shouldRedactSensitive ? redactBleLogData(normalized) : normalized;
  DeviceLog.instance.debug('ble', message, data: safeData);

  // Keep console noise low outside debug.
  if (kDebugMode) {
    debugPrint('[ble] $message${safeData == null ? '' : ' $safeData'}');
  }
}

/// Returns a redacted copy of [data] suitable for production logs.
///
/// This intentionally removes/obscures:
/// - anonymous IDs
/// - device addresses
/// - manufacturer payload bytes
Map<String, Object?>? redactBleLogData(Map<String, Object?>? data) {
  if (data == null || data.isEmpty) return data;
  final result = <String, Object?>{};
  for (final entry in data.entries) {
    result[entry.key] = _redactValue(entry.key, entry.value);
  }
  return result;
}

/// Normalizes [data] into a JSON-encodable structure.
///
/// This avoids DeviceLog JSON encoding failures when values include:
/// - `Uint8List`
/// - nested `Map` with non-string keys (e.g. manufacturerData keyed by int)
/// - other non-JSON-native objects
Map<String, Object?>? normalizeBleLogData(Map<String, Object?>? data) {
  if (data == null || data.isEmpty) return data;
  final out = <String, Object?>{};
  for (final entry in data.entries) {
    out[entry.key] = _jsonify(entry.value);
  }
  return out;
}

Object? _jsonify(Object? value) {
  if (value == null) return null;
  if (value is num || value is bool || value is String) return value;

  if (value is Uint8List) {
    return value.toList(growable: false);
  }

  if (value is Map) {
    final mapped = <String, Object?>{};
    for (final e in value.entries) {
      mapped[e.key.toString()] = _jsonify(e.value);
    }
    return mapped;
  }

  if (value is Iterable) {
    return value.map(_jsonify).toList(growable: false);
  }

  return value.toString();
}

Object? _redactValue(String key, Object? value) {
  if (_sensitiveKeys.contains(key)) {
    return _redactSensitiveValue(key, value);
  }

  // Deep-redact nested structures.
  if (value is Map) {
    final mapped = <String, Object?>{};
    for (final e in value.entries) {
      final k = e.key;
      if (k is String) {
        mapped[k] = _redactValue(k, e.value);
      } else {
        mapped[k.toString()] = _redactValue(k.toString(), e.value);
      }
    }
    return mapped;
  }

  if (value is List) {
    return value.map((v) => _redactValue(key, v)).toList(growable: false);
  }

  return value;
}

Object _redactSensitiveValue(String key, Object? value) {
  if (key == 'manufacturerData' ||
      key == 'manufacturerPayload' ||
      key == 'manufacturerPayloadFull' ||
      key == 'mfgData') {
    if (value is Uint8List) return '<redacted ${value.length} bytes>';
    if (value is List) return '<redacted ${value.length} bytes>';
    if (value is Map) return '<redacted manufacturer map>';
    return '<redacted manufacturer payload>';
  }

  // anonymous IDs + device addresses: always fully redact.
  if (value == null) return '<redacted>';
  return '<redacted>';
}
