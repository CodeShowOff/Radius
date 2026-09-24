import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';
import 'ble_device.dart';
import 'ble_diagnostics.dart';
import 'ble_uuid_encoder.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

/// Simplified BLE scanner for discovering nearby Radius devices.
///
/// Scans for all BLE devices, extracts username from Service Data (0xBEEF).
/// Tracks both raw (all) and parsed (Radius only) devices for diagnostics.
class BleScanner {
  final Map<String, BleDevice> _discoveredDevices = {};
  final Map<String, RawBleDevice> _rawDevices = {};
  final _devicesController = StreamController<List<BleDevice>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _staleDeviceTimer;
  bool _isScanning = false;
  String? _lastError;

  final BleDiagnosticsService _diagnostics = BleDiagnosticsService();

  /// Stream of discovered nearby devices (Radius only).
  Stream<List<BleDevice>> get devicesStream => _devicesController.stream;

  /// Currently discovered Radius devices.
  List<BleDevice> get discoveredDevices => _discoveredDevices.values.toList();

  /// All raw BLE devices seen (for diagnostics).
  List<RawBleDevice> get rawDevices => _rawDevices.values.toList();

  /// Whether scanning is currently active.
  bool get isScanning => _isScanning;

  /// Last error message from scanning operations.
  String? get lastError => _lastError;

  /// Starts scanning for ALL nearby BLE devices.
  /// No UUID filter - we filter in code to track both raw and Radius devices.
  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    _lastError = null;
    _diagnostics.updateScanning(true);

    // Clear previous scan results
    _discoveredDevices.clear();
    _rawDevices.clear();
    _devicesController.add([]);

    // Start the stale device cleanup timer (10 seconds)
    _startStaleDeviceTimer();

    try {
      // Cancel any existing subscription first
      await _scanSubscription?.cancel();

      // Set up scan result listener
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        _handleScanResults,
        onError: (error) {
          _lastError = 'Scan error: $error';
          _isScanning = false;
          _diagnostics.updateScanning(false);
          _diagnostics.updateError('Scan error: $error');
          _log('[BleScanner] Scan error: $error');
        },
      );

      _log('[BleScanner] Starting scan for ALL devices (no UUID filter)');

      // Scan ALL devices - no UUID filter
      // This allows us to see raw device count vs parsed Radius devices
      await FlutterBluePlus.startScan(
        androidScanMode: AndroidScanMode.lowLatency,
        continuousUpdates: true,
      );

      _log('[BleScanner] Scan started successfully');
    } catch (e) {
      _lastError = 'Failed to start scan: $e';
      _isScanning = false;
      _diagnostics.updateScanning(false);
      _diagnostics.updateError('Failed to start scan: $e');
      _log('[BleScanner] Failed to start scan: $e');
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _staleDeviceTimer?.cancel();
      _staleDeviceTimer = null;
    }
  }

  /// Stops scanning.
  ///
  /// Does NOT clear discovered devices - they remain until clearDevices() is called.
  Future<void> stopScan() async {
    if (!_isScanning) return;

    _isScanning = false;
    _diagnostics.updateScanning(false);
    _staleDeviceTimer?.cancel();
    _staleDeviceTimer = null;

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      // Ignore stop errors
    }

    // NOTE: Don't clear devices here - keep results visible after scan stops.
    // Devices are cleared when a new scan starts or clearDevices() is called.
  }

  /// Handles incoming scan results.
  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      _processScanResult(result);
    }

    // Update diagnostics with raw and parsed counts
    _diagnostics.updateRawDevices(
      _rawDevices.values.toList(),
      _discoveredDevices.length,
    );

    // Emit updated device list (Radius devices only)
    _devicesController.add(_discoveredDevices.values.toList());
  }

  /// Processes a single scan result.
  /// Tracks ALL devices in _rawDevices, and Radius devices in _discoveredDevices.
  void _processScanResult(ScanResult result) {
    try {
      final deviceId = result.device.remoteId.toString();
      final deviceName = result.device.advName;
      final localName = result.advertisementData.advName;
      final serviceUuids = result.advertisementData.serviceUuids;
      final serviceData = result.advertisementData.serviceData;
      final now = DateTime.now();

      // Track only app UUID for diagnostics (not all raw data)
      final appServiceUuids = serviceUuids
          .where((uuid) => uuid
              .toString()
              .toLowerCase()
              .contains(BleConstants.radiusServiceUuid16bit.toLowerCase()))
          .map((g) => g.toString())
          .toList();

      // Only store device if it has our app UUID
      if (appServiceUuids.isNotEmpty) {
        _rawDevices[deviceId] = RawBleDevice(
          deviceId: deviceId,
          name: localName.isNotEmpty ? localName : deviceName,
          rssi: result.rssi,
          serviceUuids: appServiceUuids,
          serviceData: {}, // Don't collect raw service data
          lastSeen: now,
        );
      }

      // Now check if this is a Radius device and extract username
      String? username;
      bool isRadiusDevice = false;

      // Strategy 1: Try UUID encoding first (works for iOS background)
      // Check all service UUIDs to see if any encode a username
      for (final uuid in serviceUuids) {
        final uuidStr = uuid.toString().toUpperCase();
        if (BleUuidEncoder.isRadiusUuid(uuidStr)) {
          isRadiusDevice = true;
          username = BleUuidEncoder.decodeUuidToUsername(uuidStr);
          if (username != null) {
            _log('[BleScanner] âœ“ Decoded username from UUID: $username');
            break;
          }
        }
      }

      // Strategy 2: Try Service Data (works for Android, iOS foreground only)
      if (username == null) {
        final radius16Lower = BleConstants.radiusServiceUuid16bit.toLowerCase();
        
        // Check if device advertises base service UUID
        for (final uuid in serviceUuids) {
          final uuidStr = uuid.toString().toLowerCase();
          if (uuidStr.contains(radius16Lower)) {
            isRadiusDevice = true;
          }
        }

        // Try to extract username from Service Data
        List<int>? serviceDataBytes;
        for (final entry in serviceData.entries) {
          final keyStr = entry.key.toString().toLowerCase();
          if (keyStr.contains(radius16Lower)) {
            serviceDataBytes = entry.value;
            isRadiusDevice = true;
            break;
          }
        }

        if (serviceDataBytes != null &&
            serviceDataBytes.length == BleConstants.usernameLength) {
          try {
            username = String.fromCharCodes(serviceDataBytes);
            // Validate it's Base62 (alphanumeric only)
            if (!RegExp(r'^[a-zA-Z0-9]{7}$').hasMatch(username)) {
              username = null;
            } else {
              _log('[BleScanner] âœ“ Decoded username from Service Data: $username');
            }
          } catch (e) {
            username = null;
          }
        }
      }

      // Strategy 3: Try LocalName (legacy iOS foreground workaround)
      if (username == null && localName.length == BleConstants.usernameLength) {
        // Check if it looks like a Radius username and we saw the service UUID
        if (isRadiusDevice && RegExp(r'^[a-zA-Z0-9]{7}$').hasMatch(localName)) {
          username = localName;
          _log('[BleScanner] âœ“ Decoded username from LocalName: $username');
        }
      }

      // Only add to Radius devices if we have valid username
      if (username == null || username.length != BleConstants.usernameLength) {
        return; // Not a valid Radius device
      }

      // Create or update Radius device
      final existingDevice = _discoveredDevices[deviceId];

      if (existingDevice != null) {
        _discoveredDevices[deviceId] = existingDevice.copyWith(
          rssi: result.rssi,
          lastSeen: now,
        );
      } else {
        _discoveredDevices[deviceId] = BleDevice(
          deviceId: deviceId,
          username: username,
          rssi: result.rssi,
          lastSeen: now,
        );
        _log('[BleScanner] âœ“ RADIUS DEVICE: $username (RSSI: ${result.rssi})');
      }
    } catch (e) {
      // Silently ignore parsing errors
    }
  }

  /// Starts the timer to remove stale devices (not seen for 10 seconds).
  void _startStaleDeviceTimer() {
    _staleDeviceTimer?.cancel();
    _staleDeviceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _removeStaleDevices(),
    );
  }

  /// Removes devices that haven't been seen for 10 seconds.
  void _removeStaleDevices() {
    final now = DateTime.now();
    const staleThreshold =
        Duration(seconds: BleConstants.deviceStaleTimeoutSeconds);

    bool removedRadius = false;
    bool removedRaw = false;

    _discoveredDevices.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen) > staleThreshold;
      if (isStale) removedRadius = true;
      return isStale;
    });

    _rawDevices.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen) > staleThreshold;
      if (isStale) removedRaw = true;
      return isStale;
    });

    if (removedRadius) {
      _devicesController.add(_discoveredDevices.values.toList());
    }

    if (removedRadius || removedRaw) {
      _diagnostics.updateRawDevices(
        _rawDevices.values.toList(),
        _discoveredDevices.length,
      );
    }
  }

  /// Clears all discovered devices.
  void clearDevices() {
    _discoveredDevices.clear();
    _rawDevices.clear();
    _devicesController.add([]);
    _diagnostics.updateRawDevices([], 0);
  }

  /// Disposes resources.
  void dispose() {
    stopScan();
    _devicesController.close();
  }
}
