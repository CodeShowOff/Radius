/// Application-wide constants
abstract class AppConstants {
  // App info
  static const String appName = 'Radius';
  static const String appVersion = '1.0.0';

  // Bluetooth configuration
  static const int bleScanDurationSeconds = 10;
  static const int bleAdvertiseIntervalMs = 1000;
  static const double proximityThresholdMeters = 10.0;
  static const double closeRangeMeters = 3.0;
  static const double mediumRangeMeters = 7.0;

  // Cache configuration
  static const int userCacheTtlMinutes = 30;
  static const int maxCachedUsers = 100;

  // UI configuration
  static const int animationDurationMs = 300;
  static const double defaultPadding = 16.0;
  static const double defaultRadius = 12.0;

  // Feature flags
  /// Enable/disable media uploads (images, audio, documents, stickers)
  /// Set to false to show "coming soon" message without Firebase Storage
  static const bool enableMediaUploads = true;
}

/// Hive box names for local storage
abstract class HiveBoxes {
  static const String userCache = 'user_cache';
  static const String settings = 'settings';
  static const String proximityLogs = 'proximity_logs';
}

/// Firestore collection names
abstract class FirestoreCollections {
  static const String users = 'users';
  static const String profiles = 'profiles';
  static const String connections = 'connections';
  static const String proximityLogs = 'proximity_logs';
}
