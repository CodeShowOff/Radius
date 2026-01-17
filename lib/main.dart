import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bootstrap/radius_bootstrap.dart';
import 'core/config/app_config.dart';

Environment _resolveEnvironment() {
  const raw = String.fromEnvironment('RADIUS_ENV', defaultValue: '');
  final normalized = raw.trim().toLowerCase();

  if (normalized.isEmpty) {
    // Default to prod in release builds unless explicitly overridden.
    return kReleaseMode ? Environment.prod : Environment.dev;
  }

  switch (normalized) {
    case 'prod':
    case 'production':
      return Environment.prod;
    case 'staging':
    case 'stage':
      return Environment.staging;
    case 'dev':
    case 'development':
      return Environment.dev;
    default:
      debugPrint('[Config] Unknown RADIUS_ENV="$raw". Falling back to dev.');
      return Environment.dev;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment configuration before any feature uses AppConfig.
  AppConfig.initialize(_resolveEnvironment());

  // Log app startup in debug mode
  if (kDebugMode) {
    debugPrint('🚀 Radius app starting in ${AppConfig.environment.name} mode');
  }

  // Render Flutter UI immediately, then perform async initialization.
  runApp(const RadiusBootstrap());
}
