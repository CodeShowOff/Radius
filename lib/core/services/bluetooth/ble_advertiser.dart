import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ble_constants.dart';
import 'ble_diagnostics.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

/// Handles BLE advertising to broadcast presence to nearby devices.
///
/// Advertises Service UUID (0xBEEF) + 7-byte username in Service Data.
/// Supports a foreground service mode that keeps advertising alive
/// even when the app is backgrounded or closed.
class BleAdvertiser {
  static const MethodChannel _channel =
  MethodChannel('com.codeshowoff.radius/ble_advertiser');

  bool _isAdvertising = false;
  bool _isForegroundServiceRunning = false;
  String? _lastError;
  String? _currentUsername;
  DateTime? _lastAdvertiseTime;

  final BleDiagnosticsService _diagnostics = BleDiagnosticsService();

  BleAdvertiser() {
    // Listen for errors from native side
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  /// Whether advertising is currently active.
  bool get isAdvertising => _isAdvertising;

  /// Last error message from advertising operations.
  String? get lastError => _lastError;

  /// The current username being advertised.
  String? get currentUsername => _currentUsername;

  /// Last time advertising was started.
  DateTime? get lastAdvertiseTime => _lastAdvertiseTime;

  /// Whether the foreground service is running.
  bool get isForegroundServiceRunning => _isForegroundServiceRunning;

  /// Starts BLE advertising with the given username.
  /// Username must be exactly 7 bytes (ASCII a-z, A-Z, 0-9).
  Future<bool> startAdvertising(String username) async {
    if (_isAdvertising && _currentUsername == username) {
      return true;
    }

    // Validate username is exactly 7 characters and alphanumeric
    if (username.length != BleConstants.usernameLength) {
      _lastError =
          'Username must be exactly ${BleConstants.usernameLength} characters';
      _diagnostics.updateError(_lastError);
      return false;
    }

    if (!RegExp(r'^[a-zA-Z0-9]{7}$').hasMatch(username)) {
      _lastError = 'Username must be alphanumeric (a-z, A-Z, 0-9)';
      _diagnostics.updateError(_lastError);
      return false;
    }

    _lastError = null;
    _currentUsername = username;

    try {
      // Convert username to bytes (7 bytes)
      final usernameBytes = Uint8List.fromList(username.codeUnits);

      _log('[BleAdvertiser] Starting advertising...');
      _log(
          '[BleAdvertiser]   Service UUID (16-bit): 0x${BleConstants.radiusServiceUuid16bit}');
      _log(
          '[BleAdvertiser]   Username: $username (${usernameBytes.length} bytes)');

      // Call native platform code
      final result = await _channel.invokeMethod<bool>('startAdvertising', {
        'serviceUuid16': BleConstants.radiusServiceUuid16bit,
        'serviceData': usernameBytes,
      });

      _isAdvertising = result ?? false;
      if (_isAdvertising) {
        _lastAdvertiseTime = DateTime.now();
        _diagnostics.updateAdvertising(true);
        _log('[BleAdvertiser] âœ“ Advertising started!');
      } else {
        _lastError = 'Native advertising returned false';
        _diagnostics.updateError(_lastError);
        _log('[BleAdvertiser] âœ— Native advertising returned false');
      }

      return _isAdvertising;
    } catch (e) {
      _lastError = 'Failed to start advertising: $e';
      _isAdvertising = false;
      _diagnostics.updateError(_lastError);
      _log('[BleAdvertiser] âœ— Failed: $e');
      return false;
    }
  }

  /// Stops BLE advertising.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    try {
      await _channel.invokeMethod('stopAdvertising');
    } catch (e) {
      // Ignore errors when stopping
    }

    _isAdvertising = false;
    _currentUsername = null;
    _diagnostics.updateAdvertising(false);
    _log('[BleAdvertiser] Advertising stopped');
  }

  /// Handles callbacks from native platform code.
  Future<void> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onAdvertisingError':
        _isAdvertising = false;
        final message = call.arguments?.toString();
        _lastError = message ?? 'Advertising failed';
        _diagnostics.updateAdvertising(false);
        _diagnostics.updateError(_lastError);
        _log('[BleAdvertiser] Error callback: $_lastError');
        break;
    }
  }

  // ============== Foreground Service ==============

  /// Starts the foreground service for persistent BLE advertising.
  ///
  /// The service keeps advertising even when the app is backgrounded or
  /// swiped away. It also automatically restarts advertising when Bluetooth
  /// is toggled off and back on.
  Future<bool> startForegroundService(String username) async {
    if (_isForegroundServiceRunning && _currentUsername == username) {
      return true;
    }

    // Validate username
    if (username.length != BleConstants.usernameLength) {
      _lastError =
          'Username must be exactly ${BleConstants.usernameLength} characters';
      _diagnostics.updateError(_lastError);
      return false;
    }

    if (!RegExp(r'^[a-zA-Z0-9]{7}$').hasMatch(username)) {
      _lastError = 'Username must be alphanumeric (a-z, A-Z, 0-9)';
      _diagnostics.updateError(_lastError);
      return false;
    }

    _currentUsername = username;

    try {
      final usernameBytes = Uint8List.fromList(username.codeUnits);

      _log('[BleAdvertiser] Starting foreground service...');

      final result =
          await _channel.invokeMethod<bool>('startForegroundService', {
        'serviceUuid16': BleConstants.radiusServiceUuid16bit,
        'serviceData': usernameBytes,
      });

      _isForegroundServiceRunning = result ?? false;
      if (_isForegroundServiceRunning) {
        _isAdvertising = true;
        _lastAdvertiseTime = DateTime.now();
        _diagnostics.updateAdvertising(true);
        _log('[BleAdvertiser] âœ“ Foreground service started!');
      } else {
        _lastError = 'Failed to start foreground service';
        _diagnostics.updateError(_lastError);
      }

      return _isForegroundServiceRunning;
    } catch (e) {
      _lastError = 'Failed to start foreground service: $e';
      _diagnostics.updateError(_lastError);
      _log('[BleAdvertiser] âœ— Foreground service failed: $e');
      return false;
    }
  }

  /// Stops the foreground service.
  Future<void> stopForegroundService() async {
    if (!_isForegroundServiceRunning) return;

    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (e) {
      // Ignore errors when stopping
    }

    _isForegroundServiceRunning = false;
    _isAdvertising = false;
    _currentUsername = null;
    _diagnostics.updateAdvertising(false);
    _log('[BleAdvertiser] Foreground service stopped');
  }

  /// Disposes resources.
  void dispose() {
    stopForegroundService();
    stopAdvertising();
  }
}
