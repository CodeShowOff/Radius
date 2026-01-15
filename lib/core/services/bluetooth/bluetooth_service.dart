import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_advertiser.dart';
import 'ble_constants.dart';
import 'ble_device.dart';
import 'ble_id_generator.dart';
import 'ble_permission_handler.dart';
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

  /// Number of nearby devices.
  int get nearbyDeviceCount => _scanner.nearbyDeviceCount;

  // ============== Initialization ==============

  /// Initializes the Bluetooth service.
  Future<bool> initialize() async {
    if (_state != BluetoothServiceState.uninitialized) {
      return _state == BluetoothServiceState.ready ||
          _state == BluetoothServiceState.active;
    }

    _setState(BluetoothServiceState.initializing);

    try {
      // Check if Bluetooth is supported
      if (!await FlutterBluePlus.isSupported) {
        _setError('Bluetooth is not supported on this device');
        _setState(BluetoothServiceState.error);
        return false;
      }

      // Check and request permissions
      final permissionStatus =
          await _permissionHandler.checkAndRequestPermissions();

      if (permissionStatus != BlePermissionStatus.granted) {
        _setError(_permissionHandler.getPermissionMessage(permissionStatus));

        if (permissionStatus == BlePermissionStatus.bluetoothOff) {
          _setState(BluetoothServiceState.bluetoothOff);
        } else {
          _setState(BluetoothServiceState.permissionDenied);
        }
        return false;
      }

      // Initialize ID generator
      _idGenerator.initialize();

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
  Future<bool> startScanning({bool continuous = false}) async {
    if (_state != BluetoothServiceState.ready &&
        _state != BluetoothServiceState.active) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      await _scanner.startScan(continuous: continuous);
      _setState(BluetoothServiceState.active);

      if (!continuous) {
        // Start interval scanning for battery optimization
        _startIntervalScanning();
      }

      return true;
    } catch (e) {
      _setError('Failed to start scanning: $e');
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
  void _startIntervalScanning() {
    _scanIntervalTimer?.cancel();
    _scanIntervalTimer = Timer.periodic(
      Duration(seconds: BleConstants.scanIntervalSeconds),
      (_) async {
        if (_state == BluetoothServiceState.active) {
          await _scanner.startScan(
            duration: Duration(seconds: BleConstants.scanDurationSeconds),
          );
        }
      },
    );
  }

  // ============== Advertising ==============

  /// Starts advertising presence to nearby devices.
  Future<bool> startAdvertising() async {
    if (_state != BluetoothServiceState.ready &&
        _state != BluetoothServiceState.active) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    try {
      final started = await _advertiser.startAdvertising();
      if (started) {
        _setState(BluetoothServiceState.active);
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
  Future<bool> startDiscovery() async {
    final scanResult = await startScanning();
    final advertiseResult = await startAdvertising();
    return scanResult && advertiseResult;
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
