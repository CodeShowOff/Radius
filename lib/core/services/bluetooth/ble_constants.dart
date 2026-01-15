/// BLE configuration constants for the Radius app.
abstract class BleConstants {
  /// Radius service UUID for BLE advertising/scanning.
  /// Using a custom UUID v4 for the app.
  static const String radiusServiceUuid =
      '00001234-0000-1000-8000-00805f9b34fb';

  /// Scan duration in seconds for each scan cycle.
  static const int scanDurationSeconds = 10;

  /// Interval between scans in seconds (for battery optimization).
  static const int scanIntervalSeconds = 30;

  /// RSSI threshold for "nearby" classification.
  /// Devices with RSSI below this are considered too far.
  static const int nearbyRssiThreshold = -80;

  /// Minimum RSSI to consider a device at all.
  static const int minimumRssiThreshold = -100;

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

  /// Manufacturer ID for BLE advertising (0xFFFF is for testing).
  /// In production, use your registered Bluetooth SIG company ID.
  static const int manufacturerId = 0xFFFF;

  /// Maximum length of anonymous ID in bytes.
  static const int maxAnonymousIdLength = 20;
}
