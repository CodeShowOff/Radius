import 'dart:async';
import 'dart:isolate';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash reporting service using Firebase Crashlytics.
///
/// Captures crashes, non-fatal errors, and provides context
/// for debugging production issues.
class CrashService {
  final FirebaseCrashlytics _crashlytics;

  CrashService({FirebaseCrashlytics? crashlytics})
      : _crashlytics = crashlytics ?? FirebaseCrashlytics.instance;

  /// Initialize crash reporting.
  ///
  /// Call this early in main() before runApp().
  Future<void> initialize() async {
    // Disable in debug mode
    await _crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

    if (kDebugMode) return;

    // Catch Flutter framework errors
    FlutterError.onError = (details) {
      _crashlytics.recordFlutterFatalError(details);
    };

    // Catch async errors not caught by Flutter
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };

    // Catch errors from isolates
    Isolate.current.addErrorListener(RawReceivePort((pair) {
      final List<dynamic> errorAndStacktrace = pair;
      _crashlytics.recordError(
        errorAndStacktrace.first,
        errorAndStacktrace.last,
        fatal: true,
      );
    }).sendPort);
  }

  /// Set user identifier for crash reports.
  ///
  /// Call on login to associate crashes with users.
  Future<void> setUserId(String userId) async {
    await _crashlytics.setUserIdentifier(userId);
  }

  /// Clear user identifier on logout.
  Future<void> clearUserId() async {
    await _crashlytics.setUserIdentifier('');
  }

  /// Set custom key-value pair for context.
  ///
  /// These appear in crash reports for debugging.
  Future<void> setCustomKey(String key, dynamic value) async {
    if (value is String) {
      await _crashlytics.setCustomKey(key, value);
    } else if (value is int) {
      await _crashlytics.setCustomKey(key, value);
    } else if (value is double) {
      await _crashlytics.setCustomKey(key, value);
    } else if (value is bool) {
      await _crashlytics.setCustomKey(key, value);
    } else {
      await _crashlytics.setCustomKey(key, value.toString());
    }
  }

  /// Set multiple custom keys at once.
  Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    for (final entry in keys.entries) {
      await setCustomKey(entry.key, entry.value);
    }
  }

  /// Log a message that appears in the crash report timeline.
  ///
  /// Use for breadcrumbs leading up to a crash.
  Future<void> log(String message) async {
    await _crashlytics.log(message);
  }

  /// Record a non-fatal error.
  ///
  /// Use for errors that are handled but should be tracked.
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
    Iterable<Object> information = const [],
  }) async {
    await _crashlytics.recordError(
      exception,
      stackTrace,
      reason: reason,
      fatal: fatal,
      information: information,
    );
  }

  /// Record a Flutter error details object.
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    await _crashlytics.recordFlutterError(details);
  }

  /// Test crash (debug only).
  void testCrash() {
    if (kDebugMode) {
      _crashlytics.crash();
    }
  }
}

/// Extension to easily log errors with context.
extension CrashServiceX on CrashService {
  /// Log an error with screen context.
  Future<void> logScreenError(
    String screen,
    dynamic error,
    StackTrace? stack,
  ) async {
    await log('Error on screen: $screen');
    await recordError(error, stack, reason: 'Screen error: $screen');
  }

  /// Log a network error.
  Future<void> logNetworkError(
    String endpoint,
    int? statusCode,
    dynamic error,
    StackTrace? stack,
  ) async {
    await log('Network error: $endpoint (status: $statusCode)');
    await setCustomKey('last_endpoint', endpoint);
    if (statusCode != null) {
      await setCustomKey('last_status_code', statusCode);
    }
    await recordError(error, stack, reason: 'Network error: $endpoint');
  }

  /// Log a Bluetooth error.
  Future<void> logBluetoothError(
    String operation,
    dynamic error,
    StackTrace? stack,
  ) async {
    await log('Bluetooth error: $operation');
    await setCustomKey('bluetooth_operation', operation);
    await recordError(error, stack, reason: 'Bluetooth error: $operation');
  }
}
