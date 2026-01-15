import 'dart:async';

import '../../core/services/bluetooth/ble_device.dart';
import '../../core/services/bluetooth/bluetooth_service.dart';
import 'data/proximity_cache.dart';
import 'data/proximity_firestore_service.dart';
import 'domain/entities/nearby_user.dart';

/// Service state for proximity detection.
enum ProximityServiceState {
  idle,
  initializing,
  discovering,
  error,
}

/// Main service for proximity detection and user discovery.
///
/// Coordinates between:
/// - BluetoothService (BLE scanning/advertising)
/// - ProximityCache (in-memory nearby users)
/// - ProximityFirestoreService (persistence and BLE ID lookup)
class ProximityService {
  final BluetoothService _bluetoothService;
  final ProximityCache _cache;
  final ProximityFirestoreService _firestoreService;

  final _stateController = StreamController<ProximityServiceState>.broadcast();
  final _nearbyUsersController = StreamController<List<NearbyUser>>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  ProximityServiceState _state = ProximityServiceState.idle;
  String? _lastError;
  StreamSubscription<List<BleDevice>>? _bleDevicesSubscription;
  StreamSubscription<List<NearbyUser>>? _cacheSubscription;
  StreamSubscription<String>? _bleIdRotationSubscription;
  StreamSubscription<BluetoothServiceState>? _bleStateSubscription;

  String? _currentUserId;

  /// Lookup cache for BLE ID -> user data (avoid repeated Firestore queries).
  final Map<String, _UserLookupResult> _userLookupCache = {};

  /// BLE IDs currently being looked up (prevent duplicate queries).
  final Set<String> _pendingLookups = {};

  ProximityService({
    required BluetoothService bluetoothService,
    ProximityCache? cache,
    ProximityFirestoreService? firestoreService,
  })  : _bluetoothService = bluetoothService,
        _cache = cache ?? ProximityCache(),
        _firestoreService = firestoreService ?? ProximityFirestoreService() {
    // Set up cache callback for encounter logging
    _cache.onUserStale = _onUserBecameStale;
  }

  // ============== Getters ==============

  /// Current service state.
  ProximityServiceState get state => _state;

  /// Last error message.
  String? get lastError => _lastError;

  /// Stream of state changes.
  Stream<ProximityServiceState> get stateStream => _stateController.stream;

  /// Stream of nearby users (sorted by proximity).
  Stream<List<NearbyUser>> get nearbyUsersStream =>
      _nearbyUsersController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Current list of nearby users.
  List<NearbyUser> get nearbyUsers => _cache.getUsersSortedByProximity();

  /// Number of nearby users.
  int get nearbyUserCount => _cache.userCount;

  /// Whether discovery is active.
  bool get isDiscovering => _state == ProximityServiceState.discovering;

  // ============== Initialization ==============

  /// Initializes the proximity service.
  /// Set [forceReinit] to true to reset and reinitialize even if already initialized.
  Future<bool> initialize(String userId, {bool forceReinit = false}) async {
    // Allow reinitialization if in error state or forced
    if (!forceReinit && _state != ProximityServiceState.idle) {
      if (_state == ProximityServiceState.error) {
        // Reset state to allow retry
        _state = ProximityServiceState.idle;
      } else {
        return true;
      }
    }

    _setState(ProximityServiceState.initializing);
    _currentUserId = userId;
    _firestoreService.setCurrentUserId(userId);
    _lastError = null; // Clear any previous error

    try {
      // Check if Bluetooth is enabled first
      var isBluetoothOn = await _bluetoothService.isBluetoothEnabled();
      if (!isBluetoothOn) {
        // Try to request Bluetooth to be turned on (shows system dialog on Android)
        await _bluetoothService.requestBluetoothOn();

        // Wait a moment for Bluetooth to fully initialize
        await Future.delayed(const Duration(milliseconds: 500));

        // Check again after request
        isBluetoothOn = await _bluetoothService.isBluetoothEnabled();
        if (!isBluetoothOn) {
          _setError('Please turn on Bluetooth to discover nearby users');
          _setState(ProximityServiceState.error);
          return false;
        }
      }

      // Initialize Bluetooth service
      final bleInitialized =
          await _bluetoothService.initialize(forceReinit: forceReinit);
      if (!bleInitialized) {
        final error =
            _bluetoothService.lastError ?? 'Failed to initialize Bluetooth';
        _setError(error);
        _setState(ProximityServiceState.error);
        return false;
      }

      // Subscribe to cache updates
      _cacheSubscription?.cancel();
      _cacheSubscription = _cache.cacheUpdates.listen((users) {
        _nearbyUsersController.add(users);
        _firestoreService.updateNearbyUsers(users);
      });

      _setState(ProximityServiceState.idle);
      return true;
    } catch (e) {
      _setError('Initialization failed: $e');
      _setState(ProximityServiceState.error);
      return false;
    }
  }

  /// Resets the service to allow reinitialization.
  void reset() {
    _bleDevicesSubscription?.cancel();
    _cacheSubscription?.cancel();
    _bleIdRotationSubscription?.cancel();
    _bleStateSubscription?.cancel();
    _bluetoothService.reset();
    _cache.clear();
    _userLookupCache.clear();
    _pendingLookups.clear();
    _state = ProximityServiceState.idle;
    _lastError = null;
  }

  // ============== Discovery ==============

  /// Starts proximity discovery (scanning and advertising).
  Future<bool> startDiscovery() async {
    if (_state == ProximityServiceState.discovering) return true;

    if (_currentUserId == null) {
      _setError('Service not initialized');
      return false;
    }

    try {
      // Cancel any existing subscriptions first
      _bleDevicesSubscription?.cancel();
      _bleStateSubscription?.cancel();

      // Subscribe to BLE device updates
      _bleDevicesSubscription = _bluetoothService.devicesStream.listen(
        _onBleDevicesUpdated,
      );

      // Subscribe to BLE state changes to update Firestore with current ID
      _bleStateSubscription = _bluetoothService.stateStream.listen((_) {
        _firestoreService.updateCurrentUserBleId(
          _bluetoothService.currentAnonymousId,
        );
      });

      // Start BLE discovery
      final started = await _bluetoothService.startDiscovery();
      if (!started) {
        final error =
            _bluetoothService.lastError ?? 'Failed to start BLE discovery';
        _setError(error);
        return false;
      }

      // Update our BLE ID in Firestore
      await _firestoreService.updateCurrentUserBleId(
        _bluetoothService.currentAnonymousId,
      );

      _setState(ProximityServiceState.discovering);
      return true;
    } catch (e) {
      _setError('Failed to start discovery: $e');
      return false;
    }
  }

  /// Stops proximity discovery.
  Future<void> stopDiscovery() async {
    await _bluetoothService.stopDiscovery();
    _bleDevicesSubscription?.cancel();
    _bleStateSubscription?.cancel();

    // Clear nearby users from Firestore
    await _firestoreService.clearNearbyUsers();

    // Clear local cache (will trigger encounter logging)
    _cache.clear();

    _setState(ProximityServiceState.idle);
  }

  // ============== BLE Device Processing ==============

  /// Handles updates from BLE scanning.
  void _onBleDevicesUpdated(List<BleDevice> devices) async {
    for (final device in devices) {
      await _processDiscoveredDevice(device);
    }
  }

  /// Processes a discovered BLE device.
  Future<void> _processDiscoveredDevice(BleDevice device) async {
    // Check if we already have this BLE ID mapped
    final existingUser = _cache.getUserByBleId(device.anonymousId);

    if (existingUser != null) {
      // Update existing user with new detection data
      _cache.updateUserDetection(
        existingUser.userId,
        bleAnonymousId: device.anonymousId,
        rssi: device.rssi,
        proximity: device.proximity,
        estimatedDistance: device.estimatedDistanceMeters,
      );
      return;
    }

    // Check lookup cache first
    final cachedLookup = _userLookupCache[device.anonymousId];
    if (cachedLookup != null) {
      if (cachedLookup.isValid && cachedLookup.userData != null) {
        _createNearbyUserFromLookup(device, cachedLookup.userData!);
      }
      return;
    }

    // Prevent duplicate lookups
    if (_pendingLookups.contains(device.anonymousId)) return;
    _pendingLookups.add(device.anonymousId);

    try {
      // Look up user in Firestore
      final userData = await _firestoreService.lookupUserByBleId(
        device.anonymousId,
      );

      // Cache the result (even if null, to prevent repeated queries)
      _userLookupCache[device.anonymousId] = _UserLookupResult(
        userData: userData,
        timestamp: DateTime.now(),
      );

      if (userData != null) {
        _createNearbyUserFromLookup(device, userData);
      }
    } finally {
      _pendingLookups.remove(device.anonymousId);
    }
  }

  /// Creates a NearbyUser from BLE device and Firestore lookup.
  void _createNearbyUserFromLookup(
    BleDevice device,
    Map<String, dynamic> userData,
  ) {
    // Don't add ourselves
    if (userData['userId'] == _currentUserId) return;

    final nearbyUser = NearbyUser(
      userId: userData['userId'] as String,
      displayName: userData['displayName'] as String,
      photoUrl: userData['photoUrl'] as String?,
      bio: userData['bio'] as String?,
      bleAnonymousId: device.anonymousId,
      rssi: device.rssi,
      proximity: device.proximity,
      estimatedDistance: device.estimatedDistanceMeters,
      firstSeen: DateTime.now(),
      lastSeen: DateTime.now(),
      isVisible: userData['isVisible'] as bool? ?? true,
    );

    _cache.upsertUser(nearbyUser);
  }

  // ============== Encounter Logging ==============

  /// Called when a user becomes stale (leaves proximity).
  void _onUserBecameStale(
    NearbyUser user,
    int peakRssi,
    BleProximity closestProximity,
  ) {
    if (_currentUserId == null) return;

    final encounter = Encounter(
      userId: _currentUserId!,
      otherUserId: user.userId,
      timestamp: user.firstSeen,
      durationSeconds: user.timeNearby.inSeconds,
      closestProximity: closestProximity.name,
      peakRssi: peakRssi,
      wasConnected: user.isConnected,
    );

    _firestoreService.logEncounter(encounter);
  }

  // ============== User Access ==============

  /// Gets the nearest user.
  NearbyUser? getNearestUser() {
    final users = nearbyUsers;
    if (users.isEmpty) return null;
    return users.first;
  }

  /// Gets users by proximity category.
  List<NearbyUser> getUsersByProximity(BleProximity proximity) {
    return _cache.getUsersByProximity(proximity);
  }

  /// Checks if a specific user is currently nearby.
  bool isUserNearby(String userId) {
    final user = _cache.getUserById(userId);
    return user?.isCurrentlyNearby ?? false;
  }

  /// Gets encounter history.
  Future<List<Encounter>> getEncounterHistory({int limit = 50}) {
    return _firestoreService.getEncounterHistory(limit: limit);
  }

  /// Stream of total encounter count.
  Stream<int> get encounterCountStream =>
      _firestoreService.encounterCountStream();

  // ============== State Management ==============

  void _setState(ProximityServiceState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  void _setError(String error) {
    _lastError = error;
    _errorController.add(error);
  }

  // ============== Cleanup ==============

  /// Clears the user lookup cache (call when BLE IDs rotate).
  void clearLookupCache() {
    // Remove stale entries (older than 20 minutes)
    final now = DateTime.now();
    _userLookupCache.removeWhere(
      (_, result) => now.difference(result.timestamp).inMinutes > 20,
    );
  }

  /// Disposes all resources.
  void dispose() {
    stopDiscovery();
    _bleDevicesSubscription?.cancel();
    _cacheSubscription?.cancel();
    _bleIdRotationSubscription?.cancel();
    _bleStateSubscription?.cancel();
    _cache.dispose();
    _firestoreService.dispose();
    _stateController.close();
    _nearbyUsersController.close();
    _errorController.close();
  }
}

/// Cached user lookup result.
class _UserLookupResult {
  final Map<String, dynamic>? userData;
  final DateTime timestamp;

  _UserLookupResult({
    this.userData,
    required this.timestamp,
  });

  /// Whether this lookup result is still valid (not expired).
  bool get isValid {
    // Cache for 15 minutes (matches BLE ID rotation)
    return DateTime.now().difference(timestamp).inMinutes < 15;
  }
}
