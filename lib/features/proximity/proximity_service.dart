import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/bluetooth/ble_device.dart';
import '../../core/services/bluetooth/bluetooth_service.dart';
import '../../core/services/firebase/username_service.dart';
import 'domain/entities/nearby_user.dart';

void _log(String message) {
  if (kDebugMode) {
    // ignore: avoid_print
    print(message);
  }
}

/// Service state for proximity detection.
enum ProximityServiceState {
  idle,
  scanning,
  scanComplete,
  error,
}

/// Simplified service for proximity detection and user discovery.
///
/// Coordinates with BluetoothService for BLE scanning/advertising.
/// Uses username directly from BLE Service Data.
/// Looks up user profiles from Firestore via UsernameService.
///
/// Advertising runs continuously while app is open.
/// Scanning runs for 15 seconds when user taps Scan button.
class ProximityService {
  final BluetoothService _bluetoothService;
  final UsernameService _usernameService;

  final _stateController = StreamController<ProximityServiceState>.broadcast();
  final _nearbyUsersController = StreamController<List<NearbyUser>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Duration for a single scan cycle
  static const Duration scanDuration = Duration(seconds: 15);

  ProximityServiceState _state = ProximityServiceState.idle;
  String? _lastError;
  StreamSubscription<List<BleDevice>>? _bleDevicesSubscription;
  StreamSubscription<BluetoothServiceState>? _bleStateSubscription;
  Timer? _scanTimer;

  String? _currentUsername;
  bool _isAdvertising = false;

  final Map<String, NearbyUser> _nearbyUsers = {};

  /// Cache for user profile lookups to avoid repeated Firestore calls
  final Map<String, Map<String, dynamic>?> _profileCache = {};

  ProximityService({
    required BluetoothService bluetoothService,
    UsernameService? usernameService,
  })  : _bluetoothService = bluetoothService,
        _usernameService = usernameService ?? UsernameService();

  // ============== Getters ==============

  /// Current service state.
  ProximityServiceState get state => _state;

  /// Last error message.
  String? get lastError => _lastError;

  /// Stream of state changes.
  Stream<ProximityServiceState> get stateStream => _stateController.stream;

  /// Stream of nearby users.
  Stream<List<NearbyUser>> get nearbyUsersStream =>
      _nearbyUsersController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Current list of nearby users.
  List<NearbyUser> get nearbyUsers => _nearbyUsers.values.toList();

  /// Number of nearby users.
  int get nearbyUserCount => _nearbyUsers.length;

  /// Whether scanning is active.
  bool get isScanning => _state == ProximityServiceState.scanning;

  /// Whether advertising is active.
  bool get isAdvertising => _isAdvertising;

  // ============== Lifecycle ==============

  /// Initializes the proximity service and starts advertising.
  ///
  /// [userId] is not used in the simplified system but kept for API consistency.
  /// [username] is the 7-character BLE username to advertise and filter self.
  Future<bool> initialize(String userId, String username) async {
    _log('[ProximityService] Initializing with username: $username');
    _currentUsername = username;

    // Subscribe to Bluetooth service state changes
    _bleStateSubscription = _bluetoothService.stateStream.listen(
      _handleBluetoothStateChange,
    );

    // Subscribe to discovered BLE devices
    _bleDevicesSubscription = _bluetoothService.devicesStream.listen(
      _handleBleDevices,
    );

    // Start advertising immediately (runs while app is open)
    final advStarted = await _bluetoothService.startAdvertising(username);
    _isAdvertising = advStarted;
    _log('[ProximityService] Advertising started: $advStarted');

    return advStarted;
  }

  /// Handles Bluetooth service state changes.
  void _handleBluetoothStateChange(BluetoothServiceState bleState) {
    if (bleState == BluetoothServiceState.error) {
      _setError(_bluetoothService.lastError ?? 'Bluetooth error');
    } else if (bleState == BluetoothServiceState.bluetoothOff) {
      _setError('Bluetooth is turned off');
      _isAdvertising = false;
    }
  }

  /// Handles discovered BLE devices.
  Future<void> _handleBleDevices(List<BleDevice> devices) async {
    // Only process if we're actively scanning
    // Check both state AND Bluetooth service scanning status
    if (_state != ProximityServiceState.scanning &&
        !_bluetoothService.isScanning) {
      if (devices.isNotEmpty) {
        _log(
            '[ProximityService] Ignoring ${devices.length} devices - not scanning (state: $_state)');
      }
      return;
    }

    if (devices.isNotEmpty) {
      _log('[ProximityService] Processing ${devices.length} devices...');
    }

    final now = DateTime.now();

    for (final device in devices) {
      final username = device.username;

      // Skip our own username
      if (username == _currentUsername) {
        _log('[ProximityService]   Skipping self: $username');
        continue;
      }

      final existingUser = _nearbyUsers[username];

      if (existingUser != null) {
        // Update existing user with new RSSI
        _nearbyUsers[username] = existingUser.copyWith(
          rssi: device.rssi,
          lastSeen: now,
        );
        _log(
            '[ProximityService]   Updated user: $username (RSSI: ${device.rssi})');
      } else {
        // New user - look up profile and add
        _log('[ProximityService]   Looking up profile for new user: $username');
        final profile = await _lookupProfile(username);

        _nearbyUsers[username] = NearbyUser(
          username: username,
          userId: profile?['userId'] as String?,
          displayName: profile?['displayName'] as String?,
          photoUrl: profile?['photoUrl'] as String?,
          bio: profile?['bio'] as String?,
          rssi: device.rssi,
          isConnected: false,
          firstSeen: now,
          lastSeen: now,
        );
        _log(
            '[ProximityService]   ✓ Added new user: $username (display: ${profile?['displayName']})');
      }
    }

    // NOTE: Don't remove users not in this batch - they may just be
    // temporarily not seen in this scan update. Only remove stale users
    // based on lastSeen timestamp when scan completes.

    // Emit updated list
    _log('[ProximityService] Total nearby users: ${_nearbyUsers.length}');
    _nearbyUsersController.add(_nearbyUsers.values.toList());
  }

  /// Looks up a user profile by username, with caching.
  Future<Map<String, dynamic>?> _lookupProfile(String username) async {
    // Check cache first
    if (_profileCache.containsKey(username)) {
      return _profileCache[username];
    }

    // Look up from Firestore
    try {
      final profile = await _usernameService.lookupUserByUsername(username);
      _profileCache[username] = profile;
      return profile;
    } catch (e) {
      // Cache the failure to avoid repeated attempts
      _profileCache[username] = null;
      return null;
    }
  }

  // ============== Scanning ==============

  /// Starts a 15-second scan for nearby users.
  ///
  /// After 15 seconds, scanning stops automatically and results are available.
  Future<bool> startScan() async {
    _log('[ProximityService] startScan() called, current state: $_state');

    if (_state == ProximityServiceState.scanning) {
      _log('[ProximityService] Already scanning, returning true');
      return true;
    }

    if (_currentUsername == null) {
      _setError('Username not set - call initialize first');
      _log('[ProximityService] Error: Username not set');
      return false;
    }

    // Clear previous results
    _nearbyUsers.clear();
    _nearbyUsersController.add([]);

    _log('[ProximityService] Starting BLE scan...');
    final started = await _bluetoothService.startScanning();
    if (!started) {
      _setError(_bluetoothService.lastError ?? 'Failed to start scanning');
      _log(
          '[ProximityService] Failed to start scanning: ${_bluetoothService.lastError}');
      return false;
    }

    _setState(ProximityServiceState.scanning);
    _log('[ProximityService] ✓ Scan started! Will run for 15 seconds.');

    // Auto-stop after 15 seconds
    _scanTimer?.cancel();
    _scanTimer = Timer(scanDuration, () {
      _log('[ProximityService] 15-second timer expired, stopping scan');
      stopScan();
    });

    return true;
  }

  /// Stops scanning manually.
  Future<void> stopScan() async {
    _log('[ProximityService] stopScan() called');
    _scanTimer?.cancel();
    _scanTimer = null;

    await _bluetoothService.stopScanning();

    _log(
        '[ProximityService] Scan complete. Found ${_nearbyUsers.length} nearby users.');
    // Emit final results and mark scan as complete
    _nearbyUsersController.add(_nearbyUsers.values.toList());
    _setState(ProximityServiceState.scanComplete);
  }

  // ============== Legacy Discovery (deprecated) ==============

  /// Starts proximity discovery.
  /// @deprecated Use startScan() instead.
  Future<bool> startDiscovery() async {
    return startScan();
  }

  /// Stops proximity discovery.
  /// @deprecated Use stopScan() instead.
  Future<void> stopDiscovery() async {
    await stopScan();
    // Also stop advertising for legacy compatibility
    await _bluetoothService.stopAdvertising();
    _isAdvertising = false;
  }

  // ============== State Management ==============

  void _setState(ProximityServiceState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(_state);
  }

  void _setError(String error) {
    _lastError = error;
    _errorController.add(error);
    _setState(ProximityServiceState.error);
  }

  // ============== Cleanup ==============

  /// Clears the profile cache.
  void clearProfileCache() {
    _profileCache.clear();
  }

  /// Clears discovered users (for UI reset).
  void clearNearbyUsers() {
    _nearbyUsers.clear();
    _nearbyUsersController.add([]);
    _setState(ProximityServiceState.idle);
  }

  /// Stops advertising (call when app goes to background).
  Future<void> stopAdvertisingOnly() async {
    await _bluetoothService.stopAdvertising();
    _isAdvertising = false;
  }

  /// Restarts advertising (call when app comes to foreground).
  Future<void> restartAdvertising() async {
    if (_currentUsername != null && !_isAdvertising) {
      final started =
          await _bluetoothService.startAdvertising(_currentUsername!);
      _isAdvertising = started;
    }
  }

  /// Disposes resources.
  Future<void> dispose() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _bluetoothService.stopScanning();
    await _bluetoothService.stopAdvertising();
    await _bleDevicesSubscription?.cancel();
    await _bleStateSubscription?.cancel();
    _bleDevicesSubscription = null;
    _bleStateSubscription = null;
    await _stateController.close();
    await _nearbyUsersController.close();
    await _errorController.close();
    _profileCache.clear();
  }
}
