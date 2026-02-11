import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_advertiser.dart';
import 'ble_device.dart';
import 'ble_permission_handler.dart';
import 'ble_scanner.dart';

/// BLE service state.
enum BluetoothServiceState {
  /// Service is not initialized.
  uninitialized,

  /// Service is ready to use.
  ready,

  /// Service is active (scanning and/or advertising).
  active,

  /// Service encountered an error.
  error,

  /// Bluetooth is turned off.
  bluetoothOff,

  /// Required permissions not granted.
  permissionDenied,
}

/// Simplified Bluetooth service coordinating scanning and advertising.
///
/// No complex state management, no foreground/background logic, no diagnostics.
/// Just simple start/stop for advertising and scanning.
class BluetoothService {
  final BlePermissionHandler _permissionHandler;
  final BleScanner _scanner;
  final BleAdvertiser _advertiser;

  final _stateController = StreamController<BluetoothServiceState>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  BluetoothServiceState _state = BluetoothServiceState.uninitialized;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  String? _lastError;
  String? _currentUsername;

  BluetoothService({
    BlePermissionHandler? permissionHandler,
    BleScanner? scanner,
    BleAdvertiser? advertiser,
  })  : _permissionHandler = permissionHandler ?? BlePermissionHandler(),
        _scanner = scanner ?? BleScanner(),
        _advertiser = advertiser ?? BleAdvertiser();

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

  /// The current username being advertised.
  String? get currentUsername => _currentUsername;

  /// Whether the foreground service is running.
  bool get isForegroundServiceRunning => _advertiser.isForegroundServiceRunning;

  /// Last error message.
  String? get lastError => _lastError;

  // ============== Bluetooth State Helpers ==============

  /// Checks if Bluetooth is currently enabled.
  Future<bool> isBluetoothEnabled() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  /// Requests to turn Bluetooth on.
  Future<void> requestBluetoothOn() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      // Platform may not support turnOn (iOS doesn't allow it)
      _setError('Cannot enable Bluetooth programmatically on this device');
    }
  }

  // ============== Initialization ==============

  /// Initializes the Bluetooth service.
  Future<bool> initialize() async {
    if (_state != BluetoothServiceState.uninitialized) {
      return _state == BluetoothServiceState.ready ||
          _state == BluetoothServiceState.active;
    }

    try {
      // Check if Bluetooth is supported
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        _setError('Bluetooth is not supported on this device');
        return false;
      }

      // Listen to adapter state changes
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen(
        _handleAdapterStateChange,
      );

      // Check current adapter state with timeout to prevent hanging
      try {
        final adapterState = await FlutterBluePlus.adapterState.first
            .timeout(const Duration(seconds: 3));
        if (adapterState != BluetoothAdapterState.on) {
          _setState(BluetoothServiceState.bluetoothOff);
          return false;
        }
      } catch (e) {
        // Timeout or error getting adapter state - assume Bluetooth might be off
        // but don't block initialization
        _setState(BluetoothServiceState.bluetoothOff);
        return false;
      }

      _setState(BluetoothServiceState.ready);
      return true;
    } catch (e) {
      _setError('Failed to initialize Bluetooth: $e');
      return false;
    }
  }

  /// Handles Bluetooth adapter state changes.
  void _handleAdapterStateChange(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.on) {
      if (_state == BluetoothServiceState.bluetoothOff) {
        _setState(BluetoothServiceState.ready);
      }
    } else {
      _setState(BluetoothServiceState.bluetoothOff);
      // Stop scanning when Bluetooth is turned off.
      // Do NOT stop foreground advertising — the native service handles
      // BT state changes itself and will auto-restart when BT comes back.
      stopScanning();
    }
  }

  // ============== Permission Handling ==============

  /// Checks and requests BLE permissions.
  Future<bool> checkAndRequestPermissions() async {
    final status = await _permissionHandler.checkAndRequestPermissions(
      needsScan: true,
      needsAdvertise: true,
    );

    if (status == BlePermissionStatus.granted) {
      return true;
    }

    if (status == BlePermissionStatus.permanentlyDenied ||
        status == BlePermissionStatus.permissionDeniedShowSettings) {
      _setState(BluetoothServiceState.permissionDenied);
      _setError('Bluetooth permissions permanently denied');
      return false;
    }

    _setState(BluetoothServiceState.permissionDenied);
    _setError('Bluetooth permissions not granted');
    return false;
  }

  /// Opens app settings for permission management.
  Future<void> openAppSettings() async {
    await _permissionHandler.openSettings();
  }

  // ============== Advertising ==============

  /// Starts BLE advertising only.
  ///
  /// [username] must be exactly 7 characters (ASCII a-z, A-Z, 0-9).
  /// Call this when the app opens to make user discoverable.
  Future<bool> startAdvertising(String username) async {
    // Ensure initialized
    if (_state == BluetoothServiceState.uninitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    // Check Bluetooth state
    if (_state == BluetoothServiceState.bluetoothOff) {
      _setError('Bluetooth is turned off');
      return false;
    }

    // Check permissions
    final hasPermissions = await checkAndRequestPermissions();
    if (!hasPermissions) {
      return false;
    }

    _currentUsername = username;

    // Start advertising
    final advertisingStarted = await _advertiser.startAdvertising(username);
    if (!advertisingStarted) {
      _setError('Failed to start advertising: ${_advertiser.lastError}');
      return false;
    }

    _setState(BluetoothServiceState.active);
    return true;
  }

  /// Stops BLE advertising only.
  Future<void> stopAdvertising() async {
    await _advertiser.stopAdvertising();
    _currentUsername = null;

    // Only go back to ready if we're not scanning
    if (!_scanner.isScanning && _state == BluetoothServiceState.active) {
      _setState(BluetoothServiceState.ready);
    }
  }

  // ============== Foreground Service Advertising ==============

  /// Starts BLE advertising via a foreground service.
  ///
  /// This keeps advertising alive even when the app is backgrounded or
  /// swiped away. A persistent notification is shown.
  ///
  /// [username] must be exactly 7 characters (ASCII a-z, A-Z, 0-9).
  Future<bool> startForegroundAdvertising(String username) async {
    // Ensure initialized
    if (_state == BluetoothServiceState.uninitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    // Check Bluetooth state
    if (_state == BluetoothServiceState.bluetoothOff) {
      _setError('Bluetooth is turned off');
      return false;
    }

    // Check permissions
    final hasPermissions = await checkAndRequestPermissions();
    if (!hasPermissions) return false;

    _currentUsername = username;

    final started = await _advertiser.startForegroundService(username);
    if (!started) {
      _setError(
          'Failed to start foreground advertising: ${_advertiser.lastError}');
      return false;
    }

    _setState(BluetoothServiceState.active);
    return true;
  }

  /// Stops the foreground service advertising.
  Future<void> stopForegroundAdvertising() async {
    await _advertiser.stopForegroundService();
    _currentUsername = null;

    if (!_scanner.isScanning && _state == BluetoothServiceState.active) {
      _setState(BluetoothServiceState.ready);
    }
  }

  // ============== Scanning ==============

  /// Starts BLE scanning only.
  ///
  /// Call this when user taps the Scan button.
  Future<bool> startScanning() async {
    // Ensure initialized
    if (_state == BluetoothServiceState.uninitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }

    // Check Bluetooth state
    if (_state == BluetoothServiceState.bluetoothOff) {
      _setError('Bluetooth is turned off');
      return false;
    }

    // Check permissions
    final hasPermissions = await checkAndRequestPermissions();
    if (!hasPermissions) {
      return false;
    }

    // Start scanning
    try {
      await _scanner.startScan();
    } catch (e) {
      _setError('Failed to start scanning: $e');
      return false;
    }

    _setState(BluetoothServiceState.active);
    return true;
  }

  /// Stops BLE scanning only.
  Future<void> stopScanning() async {
    await _scanner.stopScan();

    // Only go back to ready if we're not advertising
    if (!_advertiser.isAdvertising && _state == BluetoothServiceState.active) {
      _setState(BluetoothServiceState.ready);
    }
  }

  // ============== Legacy Discovery (Scan + Advertise) ==============

  /// Starts BLE discovery (scanning and advertising).
  /// @deprecated Use startAdvertising() and startScanning() separately.
  Future<bool> startDiscovery(String username) async {
    final advStarted = await startAdvertising(username);
    if (!advStarted) return false;

    final scanStarted = await startScanning();
    if (!scanStarted) {
      await stopAdvertising();
      return false;
    }

    return true;
  }

  /// Stops BLE discovery (scanning and advertising).
  /// @deprecated Use stopAdvertising() and stopScanning() separately.
  Future<void> stopDiscovery() async {
    await stopScanning();
    await stopAdvertising();
  }

  // ============== State Management ==============

  void _setState(BluetoothServiceState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(_state);
  }

  void _setError(String error) {
    _lastError = error;
    _errorController.add(error);
    if (_state != BluetoothServiceState.bluetoothOff &&
        _state != BluetoothServiceState.permissionDenied) {
      _setState(BluetoothServiceState.error);
    }
  }

  // ============== Cleanup ==============

  /// Disposes resources.
  Future<void> dispose() async {
    await stopDiscovery();
    await stopForegroundAdvertising();
    await _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
    await _stateController.close();
    await _errorController.close();
    _scanner.dispose();
    _advertiser.dispose();
  }
}
