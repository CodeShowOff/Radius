import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_advertiser.dart';
import 'ble_constants.dart';
import 'ble_diagnostics.dart';
import 'ble_device.dart';
import 'ble_id_generator.dart';
import 'ble_permission_handler.dart';
import 'ble_range_mode.dart';
import 'ble_scanner.dart';

/// BLE service state.
enum BluetoothServiceState {
  /// Service is not initialized.
  uninitialized,

  /// Service is initializing.
  initializing,

  /// Service is ready but not active.
  ready,

  /// Service is actively scanning/advertising.
  active,

  /// Service encountered an error.
  error,

  /// Bluetooth is turned off.
  bluetoothOff,

  /// Required permissions not granted.
  permissionDenied,
}

/// Main Bluetooth service coordinating scanning and advertising.
class BluetoothService {
  final BlePermissionHandler _permissionHandler;
  final BleIdGenerator _idGenerator;
  final BleScanner _scanner;
  late final BleAdvertiser _advertiser;

  final _stateController = StreamController<BluetoothServiceState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  BluetoothServiceState _state = BluetoothServiceState.uninitialized;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _scanIntervalTimer;
  String? _lastError;

  BluetoothService({
    BlePermissionHandler? permissionHandler,
    BleIdGenerator? idGenerator,
    BleScanner? scanner,
  })  : _permissionHandler = permissionHandler ?? BlePermissionHandler(),
        _idGenerator = idGenerator ?? BleIdGenerator(),
        _scanner = scanner ?? BleScanner() {
    _advertiser = BleAdvertiser(idGenerator: _idGenerator);
  }

  // ============== Getters ==============

  /// Current service state.
  BluetoothServiceState get state => _state;

  /// Stream of state changes.
  Stream<BluetoothServiceState> get stateStream => _stateController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Stream of discovered devices.
  Stream<List<BleDevice>> get devicesStream => _scanner.devicesStream;

  /// Currently discovered devices.
  List<BleDevice> get discoveredDevices => _scanner.discoveredDevices;

  /// Whether scanning is active.
  bool get isScanning => _scanner.isScanning;

  /// Whether advertising is active.
  bool get isAdvertising => _advertiser.isAdvertising;

  /// The current anonymous ID being used.
  String get currentAnonymousId => _idGenerator.currentAnonymousId;

  /// Last error message.
  String? get lastError => _lastError;

  /// Stream of anonymous ID rotations.
  ///
  /// Useful for updating the user's current BLE identifier in Firestore.
  Stream<String> get idRotationStream => _idGenerator.idRotationStream;

  /// Best-effort diagnostics snapshot for debugging discovery.
  BleDiagnosticsSnapshot get diagnostics => BleDiagnosticsSnapshot(
        isScanning: _scanner.isScanning,
        isAdvertising: _advertiser.isAdvertising,
        lastError: _lastError,
        scanBatchCount: _scanner.scanBatchCount,
        rawScanResultCount: _scanner.rawScanResultCount,
        msdMatchedCount: _scanner.msdMatchedCount,
        parsedRadiusCount: _scanner.parsedRadiusCount,
        filteredByRssiCount: _scanner.filteredByRssiCount,
        filteredInvalidPayloadCount: _scanner.filteredInvalidPayloadCount,
      );

  /// Number of nearby devices.
  int get nearbyDeviceCount => _scanner.nearbyDeviceCount;

  // ============== Initialization ==============

  /// Initializes the Bluetooth service.
  /// Set [forceReinit] to true to reset and reinitialize even if already initialized.
  Future<bool> initialize({bool forceReinit = false}) async {
    // Allow reinitialization if in error/bluetoothOff state or if forced
    if (!forceReinit && _state != BluetoothServiceState.uninitialized) {
      // If already ready or active, return true
      if (_state == BluetoothServiceState.ready ||
          _state == BluetoothServiceState.active) {
        return true;
      }
      // If in error or bluetoothOff state, allow re-initialization
      if (_state != BluetoothServiceState.error &&
          _state != BluetoothServiceState.bluetoothOff &&
          _state != BluetoothServiceState.permissionDenied) {
        return false;
      }
    }

    _setState(BluetoothServiceState.initializing);

    try {
      // Enable verbose logging in debug mode
      if (kDebugMode) {
        FlutterBluePlus.setLogLevel(LogLevel.verbose, color: false);
        debugPrint('[BLE] Initializing Bluetooth service...');
      }

      // Check if Bluetooth is supported
      if (!await FlutterBluePlus.isSupported) {
        _setError('Bluetooth is not supported on this device');
        _setState(BluetoothServiceState.error);
        return false;
      }

      // Check and request permissions
      final permissionStatus =
          await _permissionHandler.checkAndRequestPermissions();

      if (permissionStatus == BlePermissionStatus.bluetoothOff) {
        // Bluetooth is off, try to turn it on (shows system dialog on Android)
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));
        _setState(BluetoothServiceState.bluetoothOff);

        // Request user to turn on Bluetooth
        final turnedOn = await _permissionHandler.requestBluetoothOn();
        if (!turnedOn) {
          return false;
        }

        // Wait a moment for Bluetooth to fully initialize
        await Future.delayed(const Duration(milliseconds: 500));

        // Re-check Bluetooth state
        final isOn = await _permissionHandler.isBluetoothOn();
        if (!isOn) {
          return false;
        }

        // Bluetooth is now on, continue initialization
      } else if (permissionStatus != BlePermissionStatus.granted) {
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));
        _setState(BluetoothServiceState.permissionDenied);
        return false;
      }

      // Initialize ID generator
      _idGenerator.initialize();

      // Best-effort diagnostics: advertising support varies by device.
      // We don't hard-fail initialization if advertising isn't supported,
      // because scanning can still work and the user can still discover others.
      final caps = await _advertiser.getCapabilities();
      final advertisingSupported = caps['isAdvertisingSupported'];
      if (advertisingSupported is bool && advertisingSupported == false) {
        if (kDebugMode) {
          debugPrint('[BLE] Advertising not supported on this device');
        }
      }

      // Listen for Bluetooth adapter state changes
      _adapterStateSubscription = _permissionHandler.adapterStateStream.listen(
        _handleAdapterStateChange,
      );

      _setState(BluetoothServiceState.ready);
      return true;
    } catch (e) {
      _setError('Failed to initialize Bluetooth: $e');
      _setState(BluetoothServiceState.error);
      return false;
    }
  }

  // ============== Scanning ==============

  /// Starts scanning for nearby devices.
  Future<bool> startScanning({
    bool continuous = false,
    BleRangeMode rangeMode = BleRangeMode.large,
    Duration? duration,
    bool intervalScan = false,
  }) async {
    if (_state != BluetoothServiceState.ready &&
        _state != BluetoothServiceState.active) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      await _scanner.startScan(
        duration: duration,
        continuous: continuous,
        androidScanMode:
            continuous ? AndroidScanMode.lowLatency : AndroidScanMode.balanced,
        minRssiThreshold: rangeMode.minRssiThreshold,
      );
      _setState(BluetoothServiceState.active);

      if (!continuous && intervalScan) {
        // Optional interval scanning for battery optimization.
        _startIntervalScanning(rangeMode);
      }

      return true;
    } catch (e) {
      _setError(_scanner.lastError ?? 'Failed to start scanning: $e');
      return false;
    }
  }

  /// Stops scanning for nearby devices.
  Future<void> stopScanning() async {
    _scanIntervalTimer?.cancel();
    await _scanner.stopScan();

    if (!_advertiser.isAdvertising) {
      _setState(BluetoothServiceState.ready);
    }
  }

  /// Starts interval-based scanning for battery optimization.
  void _startIntervalScanning(BleRangeMode rangeMode) {
    _scanIntervalTimer?.cancel();
    _scanIntervalTimer = Timer.periodic(
      const Duration(seconds: BleConstants.scanIntervalSeconds),
      (_) async {
        if (_state == BluetoothServiceState.active) {
          await _scanner.startScan(
            duration: const Duration(
                seconds: BleConstants.intervalScanDurationSeconds),
            androidScanMode: AndroidScanMode.lowPower,
            minRssiThreshold: rangeMode.minRssiThreshold,
          );
        }
      },
    );
  }

  // ============== Advertising ==============

  /// Starts advertising presence to nearby devices.
  Future<bool> startAdvertising({
    BleRangeMode rangeMode = BleRangeMode.large,
  }) async {
    if (_state != BluetoothServiceState.ready &&
        _state != BluetoothServiceState.active) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      final started = await _advertiser.startAdvertising(rangeMode: rangeMode);
      if (started) {
        _setState(BluetoothServiceState.active);
      } else {
        _setError(_advertiser.lastError ?? 'Failed to start advertising');
      }
      return started;
    } catch (e) {
      _setError('Failed to start advertising: $e');
      return false;
    }
  }

  /// Stops advertising presence.
  Future<void> stopAdvertising() async {
    await _advertiser.stopAdvertising();

    if (!_scanner.isScanning) {
      _setState(BluetoothServiceState.ready);
    }
  }

  // ============== Combined Operations ==============

  /// Starts both scanning and advertising.
  Future<bool> startDiscovery({
    BleRangeMode rangeMode = BleRangeMode.large,
    bool continuousScan = false,
  }) async {
    final scanResult = await startScanning(
      rangeMode: rangeMode,
      continuous: continuousScan,
    );
    if (!scanResult) {
      _setError(_lastError ?? 'Failed to start scanning');
      return false;
    }

    final advertiseResult = await startAdvertising(rangeMode: rangeMode);
    if (!advertiseResult) {
      final message = _lastError ?? 'Failed to start advertising';

      // Some devices support BLE scanning but not peripheral advertising.
      // In that case, keep scanning active so the user can still *find others*.
      if (_isNonFatalAdvertisingError(message)) {
        _setError('Advertising disabled: $message');
        return true;
      }

      _setError(message);
      return false;
    }

    return true;
  }

  bool _isNonFatalAdvertisingError(String message) {
    final m = message.toLowerCase();
    return m.contains('advertising not supported') ||
        m.contains('feature unsupported') ||
        m.contains('ble_unavailable') ||
        m.contains('ble unavailable');
  }

  /// Stops both scanning and advertising.
  Future<void> stopDiscovery() async {
    await stopScanning();
    await stopAdvertising();
  }

  /// Forces rotation of the anonymous ID.
  void rotateAnonymousId() {
    _idGenerator.forceRotation();
  }

  // ============== Device Access ==============

  /// Gets devices filtered by proximity.
  List<BleDevice> getDevicesByProximity(BleProximity proximity) {
    return _scanner.getDevicesByProximity(proximity);
  }

  /// Gets the nearest device.
  BleDevice? getNearestDevice() {
    final devices = discoveredDevices;
    if (devices.isEmpty) return null;
    return devices.reduce((a, b) => a.rssi > b.rssi ? a : b);
  }

  /// Clears all discovered devices.
  void clearDiscoveredDevices() {
    _scanner.clearDevices();
  }

  // ============== State Management ==============

  void _setState(BluetoothServiceState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  void _setError(String error) {
    _lastError = error;
    _errorController.add(error);
  }

  void _handleAdapterStateChange(BluetoothAdapterState adapterState) {
    if (adapterState == BluetoothAdapterState.on) {
      if (_state == BluetoothServiceState.bluetoothOff) {
        _setState(BluetoothServiceState.ready);
      }
    } else if (adapterState == BluetoothAdapterState.off) {
      _scanner.stopScan();
      _advertiser.stopAdvertising();
      _setState(BluetoothServiceState.bluetoothOff);
    }
  }

  // ============== Permissions ==============

  /// Re-checks permissions (useful after returning from settings).
  Future<BlePermissionStatus> recheckPermissions() async {
    final status = await _permissionHandler.checkAndRequestPermissions();

    if (status == BlePermissionStatus.granted &&
        _state == BluetoothServiceState.permissionDenied) {
      _setState(BluetoothServiceState.ready);
    }

    return status;
  }

  /// Resets the service state to allow reinitialization.
  /// Use this when retrying after an error.
  void reset() {
    _scanIntervalTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
    _scanner.stopScan();
    _advertiser.stopAdvertising();
    _state = BluetoothServiceState.uninitialized;
    _lastError = null;
  }

  /// Checks if Bluetooth is currently enabled.
  Future<bool> isBluetoothEnabled() async {
    return await _permissionHandler.isBluetoothOn();
  }

  /// Opens app settings for permission management.
  Future<bool> openSettings() async {
    return await _permissionHandler.openSettings();
  }

  /// Requests to turn on Bluetooth.
  Future<void> requestBluetoothOn() async {
    await _permissionHandler.requestBluetoothOn();
  }

  // ============== Cleanup ==============

  /// Disposes all resources.
  void dispose() {
    _scanIntervalTimer?.cancel();
    _adapterStateSubscription?.cancel();
    _scanner.dispose();
    _advertiser.dispose();
    _idGenerator.dispose();
    _stateController.close();
    _errorController.close();
  }
}
