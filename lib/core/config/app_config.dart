/// Application environment configuration.
///
/// Manages different settings for dev, staging, and production.
enum Environment {
  /// Development environment (local testing)
  dev,

  /// Staging environment (pre-production testing)
  staging,

  /// Production environment (live users)
  prod,
}

/// Application configuration based on environment.
class AppConfig {
  static Environment _environment = Environment.dev;

  /// Initialize with the target environment.
  static void initialize(Environment env) {
    _environment = env;
  }

  /// Current environment.
  static Environment get environment => _environment;

  /// Whether running in production.
  static bool get isProduction => _environment == Environment.prod;

  /// Whether running in development.
  static bool get isDevelopment => _environment == Environment.dev;

  /// Whether running in staging.
  static bool get isStaging => _environment == Environment.staging;

  /// Firebase project ID for current environment.
  static String get firebaseProjectId {
    switch (_environment) {
      case Environment.dev:
        return 'radius-dev';
      case Environment.staging:
        return 'radius-staging';
      case Environment.prod:
        return 'radius-prod';
    }
  }

  /// Whether to enable debug logging.
  static bool get enableDebugLogging => !isProduction;

  /// Whether to enable analytics.
  static bool get enableAnalytics => isProduction || isStaging;

  /// Whether to enable crash reporting.
  static bool get enableCrashReporting => isProduction || isStaging;

  /// Whether to enable performance monitoring.
  static bool get enablePerformanceMonitoring => isProduction;

  /// API timeout duration.
  static Duration get apiTimeout {
    switch (_environment) {
      case Environment.dev:
        return const Duration(seconds: 30);
      case Environment.staging:
        return const Duration(seconds: 15);
      case Environment.prod:
        return const Duration(seconds: 10);
    }
  }

  /// Minimum log level.
  static LogLevel get minLogLevel {
    switch (_environment) {
      case Environment.dev:
        return LogLevel.debug;
      case Environment.staging:
        return LogLevel.info;
      case Environment.prod:
        return LogLevel.warning;
    }
  }

  /// BLE scan interval for background mode.
  static Duration get bleScanInterval {
    switch (_environment) {
      case Environment.dev:
        return const Duration(seconds: 10);
      case Environment.staging:
        return const Duration(seconds: 20);
      case Environment.prod:
        return const Duration(seconds: 30);
    }
  }

  /// App Store / Play Store URLs.
  static String get appStoreUrl => 'https://apps.apple.com/app/radius/id123456789';
  static String get playStoreUrl => 'https://play.google.com/store/apps/details?id=com.yourcompany.radius';

  /// Support and legal URLs.
  static String get privacyPolicyUrl => 'https://radius.app/privacy';
  static String get termsOfServiceUrl => 'https://radius.app/terms';
  static String get supportEmail => 'support@radius.app';
  static String get supportUrl => 'https://radius.app/support';

  /// Feature flags.
  static bool get enableBackgroundLocation => isProduction;
  static bool get enablePushNotifications => true;
  static bool get enableInAppPurchases => false; // Future feature
}

/// Log levels for filtering.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}
