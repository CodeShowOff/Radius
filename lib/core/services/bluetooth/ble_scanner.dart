import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_constants.dart';
import 'ble_device.dart';
import 'ble_id_generator.dart';

/// Handles BLE scanning for nearby Radius devices.
class BleScanner {
  final Map<String, BleDevice> _discoveredDevices = {};
  final _devicesController = StreamController<List<BleDevice>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _staleDeviceTimer;
  bool _isScanning = false;
  String? _lastError;

  /// Stream of discovered nearby devices.
  Stream<List<BleDevice>> get devicesStream => _devicesController.stream;

  /// Currently discovered devices.
  List<BleDevice> get discoveredDevices => _discoveredDevices.values.toList();

  /// Whether scanning is currently active.
  bool get isScanning => _isScanning;

  /// Last error message from scanning operations.
  String? get lastError => _lastError;

  /// Starts scanning for nearby BLE devices.
  Future<void> startScan({
    Duration? duration,
    bool continuous = false,
  }) async {
    if (_isScanning) return;

    _isScanning = true;
    _lastError = null;

    // Start the stale device cleanup timer
    _startStaleDeviceTimer();

    // Configure scan settings
    final scanDuration =
        duration ?? const Duration(seconds: BleConstants.scanDurationSeconds);

    try {
      // Cancel any existing subscription first
      _scanSubscription?.cancel();

      // Set up scan result listener
      _scanSubscription = FlutterBluePlus.onScanResults.listen(
        _handleScanResults,
        onError: (error) {
          _lastError = 'Scan error: $error';
          _isScanning = false;
        },
      );

      // Start scanning with filters
      await FlutterBluePlus.startScan(
        // Filter by our service UUID to only find Radius users
        withServices: [Guid(BleConstants.radiusServiceUuid)],
        // Also scan for devices with our manufacturer data
        withMsd: [MsdFilter(0xFFFF)], // Our company ID
        // Scan duration
        timeout: continuous ? null : scanDuration,
        // Android-specific settings
        androidScanMode: AndroidScanMode.balanced,
        // Remove duplicates (we handle this ourselves for RSSI updates)
        continuousUpdates: true,
        continuousDivisor: 2, // Report every 2nd packet for battery saving
      );

      if (!continuous) {
        // For non-continuous scans, wait for completion
        await Future.delayed(scanDuration);
        await stopScan();
      }
    } catch (e) {
      _lastError = 'Failed to start scan: $e';
      _isScanning = false;
      rethrow;
    }
  }

  /// Stops the current scan.
  Future<void> stopScan() async {
    if (!_isScanning) return;

    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
    } finally {
      _isScanning = false;
      _staleDeviceTimer?.cancel();
    }
  }

  /// Handles incoming scan results.
  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      final device = _parseDevice(result);
      if (device != null) {
        _discoveredDevices[device.anonymousId] = device;
      }
    }

    _emitDevices();
  }

  /// Parses a ScanResult into a BleDevice.
  BleDevice? _parseDevice(ScanResult result) {
    // Skip devices with very weak signals
    if (result.rssi < BleConstants.minimumRssiThreshold) {
      return null;
    }

    // Try to extract anonymous ID from manufacturer data
    String? anonymousId;
    final manufacturerData = result.advertisementData.manufacturerData;

    if (manufacturerData.isNotEmpty) {
      // Look for our company ID (0xFFFF)
      final ourData = manufacturerData[0xFFFF];
      if (ourData != null) {
        anonymousId = BleIdGenerator.parseAnonymousIdFromManufacturerData(
          Uint8List.fromList(ourData),
        );
      }
    }

    // If no anonymous ID found, check service data
    if (anonymousId == null) {
      final serviceData = result.advertisementData.serviceData;
      final radiusData = serviceData[Guid(BleConstants.radiusServiceUuid)];
      if (radiusData != null && radiusData.isNotEmpty) {
        anonymousId = String.fromCharCodes(radiusData);
      }
    }

    // If still no ID, use device ID as fallback (less private but functional)
    anonymousId ??= result.device.remoteId.str.hashCode.toRadixString(16);

    final proximity = BleDevice.calculateProximity(result.rssi);

    // Only include devices within our proximity threshold
    if (result.rssi < BleConstants.nearbyRssiThreshold &&
        proximity == BleProximity.far) {
      // Device is too far, but still track it
    }

    return BleDevice(
      anonymousId: anonymousId,
      deviceId: result.device.remoteId.str,
      rssi: result.rssi,
      proximity: proximity,
      lastSeen: DateTime.now(),
      isRadiusDevice: result.advertisementData.serviceUuids
          .contains(Guid(BleConstants.radiusServiceUuid)),
      deviceName: result.advertisementData.advName.isNotEmpty
          ? result.advertisementData.advName
          : null,
    );
  }

  /// Starts timer to remove stale devices.
  void _startStaleDeviceTimer() {
    _staleDeviceTimer?.cancel();
    _staleDeviceTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _removeStaleDevices(),
    );
  }

  /// Removes devices that haven't been seen recently.
  void _removeStaleDevices() {
    final now = DateTime.now();
    const staleThreshold = Duration(
      seconds: BleConstants.deviceStaleTimeoutSeconds,
    );

    _discoveredDevices.removeWhere((_, device) {
      return now.difference(device.lastSeen) > staleThreshold;
    });

    _emitDevices();
  }

  /// Emits the current list of devices.
  void _emitDevices() {
    // Sort by proximity (closest first)
    final sorted = _discoveredDevices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    _devicesController.add(sorted);
  }

  /// Clears all discovered devices.
  void clearDevices() {
    _discoveredDevices.clear();
    _emitDevices();
  }

  /// Gets devices filtered by proximity.
  List<BleDevice> getDevicesByProximity(BleProximity proximity) {
    return _discoveredDevices.values
        .where((d) => d.proximity == proximity)
        .toList();
  }

  /// Gets count of nearby devices (within threshold).
  int get nearbyDeviceCount {
    return _discoveredDevices.values
        .where((d) => d.rssi >= BleConstants.nearbyRssiThreshold)
        .length;
  }

  /// Disposes resources.
  void dispose() {
    stopScan();
    _scanSubscription?.cancel();
    _staleDeviceTimer?.cancel();
    _devicesController.close();
  }
}
