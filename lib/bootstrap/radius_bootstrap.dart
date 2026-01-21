import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../app.dart';
import '../core/config/app_config.dart';
import '../core/di/injection.dart';
import '../core/settings/app_settings_store.dart';
import '../core/services/crash/crash_service.dart';
import '../core/services/logging/device_log.dart';
import '../core/services/notifications/notification_service.dart';
import '../core/theme/app_theme.dart';
import '../firebase_options.dart';

class RadiusBootstrap extends StatefulWidget {
  const RadiusBootstrap({super.key});

  @override
  State<RadiusBootstrap> createState() => _RadiusBootstrapState();
}

class _RadiusBootstrapState extends State<RadiusBootstrap> {
  _InitPhase _phase = _InitPhase.starting;
  String _message = 'Starting…';
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    // Start initialization after the first frame so the native splash is
    // replaced immediately by Flutter UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    try {
      _setPhase(_InitPhase.initializing, 'Configuring device…');

      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]).timeout(const Duration(seconds: 5));

      _setPhase(_InitPhase.initializing, 'Connecting to Firebase…');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 12));

      // App Check is optional, but when enabled in the Firebase console it can
      // block Firestore/Functions/Storage calls. In debug builds we activate the
      // Debug provider to avoid placeholder tokens.
      if (kDebugMode) {
        _setPhase(_InitPhase.initializing, 'Activating App Check…');
        try {
          // ignore: deprecated_member_use
          await FirebaseAppCheck.instance.activate(
            // ignore: deprecated_member_use
            androidProvider: AndroidProvider.debug,
            // ignore: deprecated_member_use
            appleProvider: AppleProvider.debug,
          ).timeout(const Duration(seconds: 5));
        } catch (e, st) {
          debugPrint('[Bootstrap] App Check activation failed: $e');
          debugPrintStack(stackTrace: st);
        }
      }

      // Register background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      if (AppConfig.enableCrashReporting) {
        _setPhase(_InitPhase.initializing, 'Starting crash reporting…');
        await CrashService().initialize().timeout(const Duration(seconds: 5));
      }

      _setPhase(_InitPhase.initializing, 'Preparing local storage…');
      await Hive.initFlutter().timeout(const Duration(seconds: 5));

      // Load persisted app settings (theme, etc.)
      final settingsBox =
          await Hive.openBox('radius_settings').timeout(const Duration(seconds: 5));
      if (!getIt.isRegistered<Box<dynamic>>(instanceName: 'radius_settings')) {
        getIt.registerSingleton<Box<dynamic>>(
          settingsBox,
          instanceName: 'radius_settings',
        );
      }
      if (!getIt.isRegistered<AppSettingsStore>()) {
        getIt.registerSingleton<AppSettingsStore>(
          AppSettingsStore(box: settingsBox),
        );
      }

      _setPhase(_InitPhase.initializing, 'Loading services…');
      await configureDependencies().timeout(const Duration(seconds: 10));

      _setPhase(_InitPhase.initializing, 'Starting diagnostics…');
      await DeviceLog.instance.init().timeout(const Duration(seconds: 5));

      DeviceLog.instance.info('app', 'Bootstrap complete', data: {
        'environment': AppConfig.environment.name,
        'crashReporting': AppConfig.enableCrashReporting,
      });

      if (!mounted) return;
      setState(() {
        _phase = _InitPhase.ready;
      });
    } on TimeoutException catch (e, st) {
      _fail('Initialization timed out: ${e.message ?? 'timeout'}', e, st);
    } catch (e, st) {
      _fail('Initialization failed: ${e.runtimeType}', e, st);
    }
  }

  void _setPhase(_InitPhase phase, String message) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  void _fail(String message, Object error, StackTrace stack) {
    // Best-effort console output for release builds where logs are harder.
    debugPrint('[Bootstrap] $message');
    debugPrint(error.toString());
    debugPrintStack(stackTrace: stack);

    // Best-effort device log (should not throw).
    try {
      DeviceLog.instance.error(
        'app',
        message,
        error: error,
        stackTrace: stack,
        data: {'environment': AppConfig.environment.name},
      );
    } catch (_) {
      // ignore
    }

    if (!mounted) return;
    setState(() {
      _phase = _InitPhase.failed;
      _message = message;
      _error = error;
      _stack = stack;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _InitPhase.ready) {
      return const RadiusApp();
    }

    // Only show bootstrap screen on failure, otherwise show blank screen
    // to avoid flashing initialization messages
    if (_phase == _InitPhase.failed) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: _BootstrapScreen(
          phase: _phase,
          message: _message,
          error: _error,
          stack: _stack,
          onRetry: () {
            setState(() {
              _phase = _InitPhase.starting;
              _message = 'Retrying…';
              _error = null;
              _stack = null;
            });
            unawaited(_initialize());
          },
        ),
      );
    }

    // Show loading screen during initialization
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.radar,
                size: 64,
                color: Colors.blue,
              ),
              SizedBox(height: 24),
              Text(
                'Radius',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

enum _InitPhase { starting, initializing, failed, ready }

class _BootstrapScreen extends StatelessWidget {
  final _InitPhase phase;
  final String message;
  final Object? error;
  final StackTrace? stack;
  final VoidCallback? onRetry;

  const _BootstrapScreen({
    required this.phase,
    required this.message,
    required this.error,
    required this.stack,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.radar,
                          size: 64,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Radius',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (phase != _InitPhase.failed) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          Text(
                            'Couldn\'t start the app',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: colorScheme.error),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          if (kDebugMode && error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                error.toString(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: onRetry,
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
