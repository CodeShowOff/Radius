import 'package:flutter/foundation.dart';

/// BLE configuration constants for the Radius app.
abstract class BleConstants {
  /// Radius service UUID for BLE advertising/scanning.
  /// Using a custom UUID v4 for the app.
  static const String radiusServiceUuid =
      '00001234-0000-1000-8000-00805f9b34fb';

  /// Scan duration in seconds for each scan cycle.
  static const int scanDurationSeconds = 30;

  /// Short scan duration used for interval/battery-optimized scan loops.
  static const int intervalScanDurationSeconds = 3;

  /// Interval between scans in seconds (for battery optimization).
  static const int scanIntervalSeconds = 15;

  /// RSSI threshold for "nearby" classification.
  /// Devices with RSSI below this are considered too far.
  static const int nearbyRssiThreshold = -80;

  /// Minimum RSSI to consider a device at all.
  static const int minimumRssiThreshold = -127;

  /// Time in seconds before a device is considered stale.
  static const int deviceStaleTimeoutSeconds = 60;

  /// Anonymous ID rotation interval in minutes for privacy.
  static const int idRotationMinutes = 15;

  /// RSSI threshold for "immediate" proximity (very close).
  static const int immediateRssiThreshold = -50;

  /// RSSI threshold for "near" proximity.
  static const int nearRssiThreshold = -70;

  /// RSSI threshold for "far" proximity.
  static const int farRssiThreshold = -85;

  /// Manufacturer ID used in debug builds.
  ///
  /// `0xFFFF` is reserved for testing and must not ship in production.
  static const int manufacturerIdDebug = 0xFFFF;

  /// Build-time configurable manufacturer ID for release builds.
  ///
  /// Set via `--dart-define=RADIUS_MANUFACTURER_ID=0x1234` (or decimal).
  /// If unset/invalid, this resolves to `0` and the app should warn in release.
  ///
  /// IMPORTANT: supply a real Bluetooth SIG Company Identifier before shipping.
  static const String _manufacturerIdEnv = String.fromEnvironment(
    'RADIUS_MANUFACTURER_ID',
    defaultValue: '',
  );

  static int get manufacturerIdProduction {
    final raw = _manufacturerIdEnv.trim();
    if (raw.isEmpty) return 0;
    final normalized = raw.toLowerCase();
    try {
      if (normalized.startsWith('0x')) {
        return int.parse(normalized.substring(2), radix: 16);
      }
      return int.parse(normalized, radix: 10);
    } catch (_) {
      return 0;
    }
  }

  /// Manufacturer ID used by the app for scanning and advertising.
  ///
  /// - Debug/profile: `manufacturerIdDebug` (testing)
  /// - Release: `manufacturerIdProduction` (must be configured)
  static int get manufacturerId =>
      kReleaseMode ? manufacturerIdProduction : manufacturerIdDebug;

  /// Maximum length of anonymous ID in bytes.

  /// Maximum length of anonymous ID in hex characters.
  ///
  /// Radius IDs are transported as packed bytes over manufacturer data,
  /// and represented in-app as uppercase hex. We use a fixed 32-hex-char ID
  /// (16 bytes) to avoid truncation/UTF-8 issues.
  static const int maxAnonymousIdLength = 32;
}
