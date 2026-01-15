import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_options.dart';
import 'core/di/injection.dart';
import 'core/services/crash/crash_service.dart';

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

  // Log app startup in debug mode
  if (kDebugMode) {
    debugPrint('🚀 Radius app starting in ${AppConfig.environment.name} mode');
  }

  // TODO: Initialize Bluetooth service
  // await getIt<BluetoothService>().initialize();

  runApp(const RadiusApp());
}
