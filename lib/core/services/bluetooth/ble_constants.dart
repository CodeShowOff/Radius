/// BLE configuration constants for the Radius app.
abstract class BleConstants {
  /// Radius base service UUID (16-bit format).
  /// 16-bit UUID: 0xBEEF (2 bytes on-air).
  ///
  /// **Platform Differences:**
  ///
  /// **Android:** Advertises with fixed UUID (0xBEEF) + username in Service Data.
  /// This works fine with foreground service, even when app is backgrounded.
  ///
  /// **iOS:** Encodes username INTO the UUID itself using hybrid UUID encoding.
  /// Format: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX (username in XXXX sections)
  /// This is necessary because iOS strips Service Data when app is backgrounded,
  /// but preserves Service UUIDs.
  ///
  /// **Scanner:** Supports both methods - checks for encoded UUIDs first (iOS),
  /// then falls back to Service Data (Android) and LocalName (legacy).
  static const String radiusServiceUuid16bit = 'BEEF';

  /// Time in seconds before a device is considered stale and removed from UI.
  static const int deviceStaleTimeoutSeconds = 10;

  /// Username/userId length in bytes (7 characters, Base62: a-z, A-Z, 0-9)
  static const int usernameLength = 7;
}
