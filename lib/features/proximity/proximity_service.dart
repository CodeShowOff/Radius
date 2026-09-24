import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/bluetooth/ble_device.dart';
import '../../core/services/bluetooth/bluetooth_service.dart';
import '../../core/services/firebase/username_service.dart';
import '../../core/settings/app_settings_store.dart';
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
/// Advertising runs via a foreground service so it persists even when the
/// app is backgrounded or closed. Scanning runs for 10 seconds on demand.
class ProximityService {
  final BluetoothService _bluetoothService;
  final UsernameService _usernameService;
  final AppSettingsStore _settingsStore;

  final _stateController = StreamController<ProximityServiceState>.broadcast();
  final _nearbyUsersController = StreamController<List<NearbyUser>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Duration for a single scan cycle
  static const Duration scanDuration = Duration(seconds: 10);

  ProximityServiceState _state = ProximityServiceState.idle;
  String? _lastError;
  StreamSubscription<List<BleDevice>>? _bleDevicesSubscription;
  StreamSubscription<BluetoothServiceState>? _bleStateSubscription;
  Timer? _scanTimer;

  String? _currentUsername;
  bool _isAdvertising = false;
  bool _isTogglingAdvertising = false;

  final Map<String, NearbyUser> _nearbyUsers = {};

  /// Cache for user profile lookups to avoid repeated Firestore calls
  final Map<String, Map<String, dynamic>?> _profileCache = {};

  ProximityService({
    required BluetoothService bluetoothService,
    required AppSettingsStore settingsStore,
    UsernameService? usernameService,
  })  : _bluetoothService = bluetoothService,
        _settingsStore = settingsStore,
        _usernameService = usernameService ?? UsernameService() {
    // CRITICAL: Set up Bluetooth state listener IMMEDIATELY on construction
    // This ensures advertising can auto-start whenever Bluetooth turns on,
    // even before initialize() is called
    _log('[ProximityService] Constructor - setting up Bluetooth state listener');
    _bleStateSubscription = _bluetoothService.stateStream.listen(
      _handleBluetoothStateChange,
    );
  }

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
  /// 
  /// If Bluetooth is off, it will wait and automatically start advertising when Bluetooth turns on.
  /// The Bluetooth state listener is set up in the constructor, so advertising auto-starts on Bluetooth enable.
  Future<bool> initialize(String userId, String username) async {
    _log('[ProximityService] ========================================');
    _log('[ProximityService] INITIALIZING with username: $username');
    _log('[ProximityService] ========================================');
    
    _currentUsername = username;

    // Note: Bluetooth state listener was already set up in constructor
    // This ensures we can react to Bluetooth changes even before initialize() is called

    // Subscribe to discovered BLE devices
    _bleDevicesSubscription?.cancel();
    _bleDevicesSubscription = _bluetoothService.devicesStream.listen(
      _handleBleDevices,
    );

    // Initialize Bluetooth service if needed
    await _bluetoothService.initialize();

    // Check if Bluetooth is enabled before trying to advertise
    final bluetoothEnabled = await _bluetoothService.isBluetoothEnabled();
    if (!bluetoothEnabled) {
      _log('[ProximityService] Bluetooth is OFF - will auto-start advertising when Bluetooth turns on');
      _isAdvertising = false;
      return true; // Return true as initialization succeeded, just waiting for Bluetooth
    }

    // Start advertising (foreground service if background advertising is enabled)
    _log('[ProximityService] Bluetooth is ON, starting advertising...');
    final useBackground = _settingsStore.getBackgroundAdvertising();
    _log('[ProximityService]   Background advertising enabled: $useBackground');

    bool advStarted;
    if (useBackground) {
      advStarted = await _bluetoothService.startForegroundAdvertising(username);
    } else {
      advStarted = await _bluetoothService.startAdvertising(username);
    }
    _isAdvertising = advStarted;
    
    if (advStarted) {
      _log('[ProximityService] âœ“ Advertising started successfully!');
    } else {
      _log('[ProximityService] âœ— Failed to start advertising: ${_bluetoothService.lastError}');
    }

    return advStarted;
  }

  /// Handles Bluetooth service state changes.
  /// 
  /// Automatically restarts advertising when Bluetooth turns on.
  /// This is called from the constructor's state listener, so it works even before initialize().
  void _handleBluetoothStateChange(BluetoothServiceState bleState) {
    _log('[ProximityService] ========================================');
    _log('[ProximityService] Bluetooth state changed to: $bleState');
    _log('[ProximityService]   Current username: $_currentUsername');
    _log('[ProximityService]   Is advertising: $_isAdvertising');
    _log('[ProximityService] ========================================');
    
    if (bleState == BluetoothServiceState.error) {
      _setError(_bluetoothService.lastError ?? 'Bluetooth error');
    } else if (bleState == BluetoothServiceState.bluetoothOff) {
      _log('[ProximityService] âš ï¸ Bluetooth turned OFF - advertising stopped');
      // Don't show error to user - BT off is a normal state, not an error
      _isAdvertising = false;
    } else if (bleState == BluetoothServiceState.ready ||
        bleState == BluetoothServiceState.active) {
      // Bluetooth is back on - restart advertising if we have a username
      if (_currentUsername != null && !_isAdvertising) {
        _log('[ProximityService] âœ… Bluetooth is ON! Restarting advertising for $_currentUsername');
        final useBackground = _settingsStore.getBackgroundAdvertising();
        Future<bool> advertiseFuture;
        if (useBackground) {
          advertiseFuture = _bluetoothService.startForegroundAdvertising(_currentUsername!);
        } else {
          advertiseFuture = _bluetoothService.startAdvertising(_currentUsername!);
        }
        advertiseFuture.then((started) {
          _isAdvertising = started;
          if (started) {
            _log('[ProximityService] âœ“âœ“âœ“ Advertising SUCCESSFULLY restarted!');
          } else {
            _log('[ProximityService] âœ—âœ—âœ— FAILED to restart advertising: ${_bluetoothService.lastError}');
          }
        });
      } else if (_currentUsername == null) {
        _log('[ProximityService] â³ Bluetooth is ON but no username set yet (waiting for initialize)');
      } else {
        _log('[ProximityService] â„¹ï¸ Bluetooth is ON and already advertising');
      }
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
          vibe: profile?['vibe'] as String?,
          mood: profile?['mood'] as String?,
          gender: profile?['gender'] as String?,
          rssi: device.rssi,
          isConnected: false,
          firstSeen: now,
          lastSeen: now,
        );
        _log(
            '[ProximityService]   âœ“ Added new user: $username (display: ${profile?['displayName']})');
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

  /// Starts a scan for nearby users.
  ///
  /// [duration] - Optional custom scan duration. If not provided, uses default 10 seconds.
  /// Users appear in real-time as they're discovered (don't wait for scan to complete).
  /// After duration expires, scanning stops automatically and results remain available.
  Future<bool> startScan({Duration? duration}) async {
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

    final scanTime = duration ?? scanDuration;

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
    _log('[ProximityService] âœ“ Scan started! Will run for ${scanTime.inSeconds} seconds.');

    // Auto-stop after specified duration
    _scanTimer?.cancel();
    _scanTimer = Timer(scanTime, () {
      _log('[ProximityService] ${scanTime.inSeconds}-second timer expired, stopping scan');
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

  /// Stops all activity and clears all data (call on sign out).
  /// Unlike dispose(), this allows the service to be reused after sign in.
  Future<void> stop() async {
    _log('[ProximityService] Stopping service...');
    _scanTimer?.cancel();
    _scanTimer = null;
    await _bluetoothService.stopScanning();
    await _bluetoothService.stopForegroundAdvertising();
    await _bluetoothService.stopAdvertising();
    _isAdvertising = false;
    _currentUsername = null;
    _nearbyUsers.clear();
    _profileCache.clear();
    _setState(ProximityServiceState.idle);
    _log('[ProximityService] Service stopped');
  }

  /// Switches between background (foreground-service) and foreground-only
  /// advertising based on [enabled]. Called when the user flips the toggle.
  /// Protected with mutex to prevent overlapping operations from rapid toggles.
  Future<void> setBackgroundAdvertising(bool enabled) async {
    if (_isTogglingAdvertising) {
      _log('[ProximityService] Already toggling advertising, ignoring duplicate request');
      return;
    }

    _isTogglingAdvertising = true;
    try {
      await _settingsStore.setBackgroundAdvertising(enabled);
      _log('[ProximityService] Background advertising set to: $enabled');

      // When DISABLING background advertising, always stop the foreground service
      // if it's running, even if _isAdvertising is false (e.g., Bluetooth is off).
      // This ensures the notification is removed and the service is properly stopped.
      if (!enabled) {
        if (_bluetoothService.isForegroundServiceRunning) {
          _log('[ProximityService] Stopping foreground service...');
          await _bluetoothService.stopForegroundAdvertising();
        }
        
        // If Bluetooth is on and we're advertising, restart with plain advertising
        if (_currentUsername != null && _isAdvertising) {
          _log('[ProximityService] Restarting with plain advertising...');
          final started = await _bluetoothService.startAdvertising(_currentUsername!);
          _isAdvertising = started;
        }
        return;
      }

      // When ENABLING background advertising, we need to be actively advertising
      if (_currentUsername == null || !_isAdvertising) {
        _log('[ProximityService] Not currently advertising, skipping switch to foreground service');
        return;
      }

      // Switch from plain advertising â†’ foreground service
      _log('[ProximityService] Switching to foreground service...');
      await _bluetoothService.stopAdvertising();
      final started = await _bluetoothService.startForegroundAdvertising(_currentUsername!);
      _isAdvertising = started;
    } finally {
      _isTogglingAdvertising = false;
    }
  }

  /// Disposes resources.
  Future<void> dispose() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _bluetoothService.stopScanning();
    // Note: we do NOT stop foreground advertising on dispose, so it persists.
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
