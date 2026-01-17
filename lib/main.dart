import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'firebase_options.dart';
import 'core/di/injection.dart';
import 'core/services/crash/crash_service.dart';
import 'core/services/logging/device_log.dart';
import 'core/services/bluetooth/ble_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize crash reporting (must be after Firebase.initializeApp)
  if (AppConfig.enableCrashReporting) {
    await CrashService().initialize();
  }

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // Initialize dependency injection
  await configureDependencies();

  // Initialize on-device diagnostics logging (best-effort).
  await DeviceLog.instance.init();

  // Safety check: do not ship with the reserved testing manufacturer ID.
  // Configure in CI/release builds via: --dart-define=RADIUS_MANUFACTURER_ID=0x1234
  if (kReleaseMode) {
    final id = BleConstants.manufacturerId;
    if (id == 0 || id == BleConstants.manufacturerIdDebug) {
      DeviceLog.instance.warning(
          'ble.config', 'Production manufacturer ID not configured',
          data: {
            'manufacturerId': id,
            'hint':
                'Set --dart-define=RADIUS_MANUFACTURER_ID=<Bluetooth SIG company id>',
          });
      debugPrint(
          '[BLE] WARNING: production manufacturer ID not configured (id=$id).');
    }
  }

  // Log app startup in debug mode
  if (kDebugMode) {
    debugPrint('🚀 Radius app starting in ${AppConfig.environment.name} mode');
  }

  DeviceLog.instance.info('app', 'App starting', data: {
    'environment': AppConfig.environment.name,
    'crashReporting': AppConfig.enableCrashReporting,
  });

  // TODO: Initialize Bluetooth service
  // await getIt<BluetoothService>().initialize();

  runApp(const RadiusApp());
}
