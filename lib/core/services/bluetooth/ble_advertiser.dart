import 'dart:async';

import 'package:flutter/services.dart';

import 'ble_constants.dart';
import 'ble_id_generator.dart';
import 'ble_range_mode.dart';

/// Handles BLE advertising to broadcast presence to nearby devices.
///
/// Uses native platform channels for Android and iOS BLE advertising.
class BleAdvertiser {
  final BleIdGenerator _idGenerator;
  static const MethodChannel _channel =
      MethodChannel('com.example.radius/ble_advertiser');

  bool _isAdvertising = false;
  String? _lastError;
  StreamSubscription<String>? _idRotationSubscription;
  BleRangeMode _currentRangeMode = BleRangeMode.large;

  BleAdvertiser({required BleIdGenerator idGenerator})
      : _idGenerator = idGenerator {
    // Listen for errors from native side
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  /// Whether advertising is currently active.
  bool get isAdvertising => _isAdvertising;

  /// Last error message from advertising operations.
  String? get lastError => _lastError;

  /// The current anonymous ID being advertised.
  String get currentAdvertisedId => _idGenerator.currentAnonymousId;

  /// Starts BLE advertising.
  Future<bool> startAdvertising(
      {BleRangeMode rangeMode = BleRangeMode.large}) async {
    if (_isAdvertising) return true;
    _lastError = null;
    _currentRangeMode = rangeMode;

    // Ensure we don't leak an old subscription if startAdvertising is retried.
    await _idRotationSubscription?.cancel();
    _idRotationSubscription = null;

    try {
      // Call native platform code
      final result = await _channel.invokeMethod<bool>('startAdvertising', {
        'anonymousId': _idGenerator.currentAnonymousId,
        'serviceUuid': BleConstants.radiusServiceUuid,
        'androidTxPowerLevel': rangeMode.androidTxPowerLevel,
        'androidAdvertiseMode': rangeMode.androidAdvertiseMode,
      });

      _isAdvertising = result ?? false;
      if (!_isAdvertising) {
        _lastError = 'Native advertising returned false';
        return false;
      }

      // Only listen for ID rotations once advertising is confirmed active.
      _idRotationSubscription = _idGenerator.idRotationStream.listen(
        (_) => _updateAdvertisement(),
      );
      return _isAdvertising;
    } catch (e) {
      _lastError = 'Failed to start advertising: $e';
      _isAdvertising = false;
      await _idRotationSubscription?.cancel();
      _idRotationSubscription = null;
      return false;
    }
  }

  /// Best-effort capabilities snapshot from native platform.
  ///
  /// On Android, this includes whether BLE advertising is supported and whether
  /// multiple advertisement is supported.
  Future<Map<String, dynamic>> getCapabilities() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getCapabilities');
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      return const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// Stops BLE advertising.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;

    await _idRotationSubscription?.cancel();
    _idRotationSubscription = null;

    try {
      await _channel.invokeMethod('stopAdvertising');
    } catch (e) {
      // Ignore errors when stopping
    }

    _isAdvertising = false;
  }

  /// Updates the advertisement with new ID after rotation.
  Future<void> _updateAdvertisement() async {
    if (!_isAdvertising) return;

    try {
      await _channel.invokeMethod('updateAdvertisement', {
        'anonymousId': _idGenerator.currentAnonymousId,
        'serviceUuid': BleConstants.radiusServiceUuid,
        'androidTxPowerLevel': _currentRangeMode.androidTxPowerLevel,
        'androidAdvertiseMode': _currentRangeMode.androidAdvertiseMode,
      });
    } catch (e) {
      // Log error but don't stop advertising
    }
  }

  /// Handles callbacks from native platform code.
  Future<void> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onAdvertisingError':
        // Error from native advertising
        _isAdvertising = false;
        await _idRotationSubscription?.cancel();
        _idRotationSubscription = null;
        final message = call.arguments?.toString();
        if (message != null && message.isNotEmpty) {
          _lastError = message;
        } else {
          _lastError = 'Advertising failed';
        }
        break;
    }
  }

  /// Gets the advertisement data for the current ID.
  Map<String, dynamic> getAdvertisementData() {
    return {
      'serviceUuid': BleConstants.radiusServiceUuid,
      'anonymousId': _idGenerator.currentAnonymousId,
      'manufacturerData': _idGenerator.createManufacturerData(),
    };
  }

  /// Disposes resources.
  void dispose() {
    stopAdvertising();
    _idRotationSubscription?.cancel();
    _idRotationSubscription = null;
  }
}
