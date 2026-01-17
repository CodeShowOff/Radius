/// BLE configuration constants for the Radius app.
abstract class BleConstants {
  /// Radius service UUID for BLE advertising/scanning.
  /// 16-bit UUID: 0xBEEF (2 bytes on-air).
  ///
  /// Note: some BLE stacks/scanner APIs may *display* this as the Bluetooth Base
  /// UUID form (0000BEEF-0000-1000-8000-00805F9B34FB), but advertising should
  /// remain 16-bit sized in the payload.
  static const String radiusServiceUuid16bit = 'BEEF';

  /// Time in seconds before a device is considered stale and removed from UI.
  static const int deviceStaleTimeoutSeconds = 10;

  /// Username/userId length in bytes (7 characters, Base62)
  static const int usernameLength = 7;
}
