import 'dart:async';

import '../../../core/services/bluetooth/ble_device.dart';
import '../domain/entities/nearby_user.dart';

/// In-memory cache for nearby users with automatic expiration.
class ProximityCache {
  /// Cache of nearby users keyed by Firebase user ID.
  final Map<String, NearbyUser> _userCache = {};

  /// Mapping of BLE anonymous IDs to Firebase user IDs.
  final Map<String, String> _bleToUserIdMap = {};

  /// Reverse mapping for quick lookups.
  final Map<String, String> _userIdToBleMap = {};

  /// Peak RSSI recorded for each user (for encounter logging).
  final Map<String, int> _peakRssi = {};

  /// Closest proximity recorded for each user.
  final Map<String, BleProximity> _closestProximity = {};

  /// Stream controller for cache updates.
  final _cacheUpdateController = StreamController<List<NearbyUser>>.broadcast();

  /// Timer for periodic stale user cleanup.
  Timer? _cleanupTimer;

  /// Duration after which a user is considered stale.
  final Duration staleThreshold;

  /// Callback when a user becomes stale (for encounter logging).
  final void Function(NearbyUser user, int peakRssi, BleProximity closestProximity)?
      onUserStale;

  ProximityCache({
    this.staleThreshold = const Duration(seconds: 60),
    this.onUserStale,
  }) {
    _startCleanupTimer();
  }

  /// Stream of cache updates.
  Stream<List<NearbyUser>> get cacheUpdates => _cacheUpdateController.stream;

  /// All cached nearby users.
  List<NearbyUser> get allUsers => _userCache.values.toList();

  /// Number of cached users.
  int get userCount => _userCache.length;

  /// Gets a user by Firebase user ID.
  NearbyUser? getUserById(String oderId) => _userCache[userId];

  /// Gets a user by BLE anonymous ID.
  NearbyUser? getUserByBleId(String bleId) {
    final oderId = _bleToUserIdMap[bleId];
    if (userId == null) return null;
    return _userCache[userId];
  }

  /// Gets the Firebase user ID for a BLE anonymous ID.
  String? getUserIdForBleId(String bleId) => _bleToUserIdMap[bleId];

  /// Checks if a BLE ID is already mapped to a user.
  bool isBleIdKnown(String bleId) => _bleToUserIdMap.containsKey(bleId);

  /// Adds or updates a BLE ID to user ID mapping.
  void mapBleIdToUserId(String bleId, String oderId) {
    // Remove old BLE ID mapping if user had a different one
    final oldBleId = _userIdToBleMap[userId];
    if (oldBleId != null && oldBleId != bleId) {
      _bleToUserIdMap.remove(oldBleId);
    }

    _bleToUserIdMap[bleId] = oderId    _userIdToBleMap[userId] = bleId;
  }

  /// Adds or updates a nearby user in the cache.
  void upsertUser(NearbyUser user) {
    final existing = _userCache[user.userId];

    if (existing != null) {
      // Update existing user
      _userCache[user.userId] = user;
    } else {
      // New user
      _userCache[user.userId] = user;
      _peakRssi[user.userId] = user.rssi;
      _closestProximity[user.userId] = user.proximity;
    }

    // Track peak RSSI (higher is closer)
    if (user.rssi > (_peakRssi[user.userId] ?? -100)) {
      _peakRssi[user.userId] = user.rssi;
    }

    // Track closest proximity
    final currentClosest = _closestProximity[user.userId];
    if (currentClosest == null || _isCloser(user.proximity, currentClosest)) {
      _closestProximity[user.userId] = user.proximity;
    }

    // Update BLE mapping
    mapBleIdToUserId(user.bleAnonymousId, user.userId);

    _emitUpdate();
  }

  /// Removes a user from the cache.
  void removeUser(String oderId) {
    final user = _userCache.remove(userId);
    if (user != null) {
      _bleToUserIdMap.remove(user.bleAnonymousId);
      _userIdToBleMap.remove(userId);

      // Notify about stale user for encounter logging
      final peakRssi = _peakRssi.remove(userId) ?? user.rssi;
      final closestProximity =
          _closestProximity.remove(userId) ?? user.proximity;
      onUserStale?.call(user, peakRssi, closestProximity);

      _emitUpdate();
    }
  }

  /// Updates a user with new BLE detection data.
  void updateUserDetection(
    String oderId, {
    required String bleAnonymousId,
    required int rssi,
    required BleProximity proximity,
    required double estimatedDistance,
  }) {
    final user = _userCache[userId];
    if (user == null) return;

    final updated = user.updateWithDetection(
      bleAnonymousId: bleAnonymousId,
      rssi: rssi,
      proximity: proximity,
      estimatedDistance: estimatedDistance,
    );

    upsertUser(updated);
  }

  /// Gets users sorted by proximity (closest first).
  List<NearbyUser> getUsersSortedByProximity() {
    final users = allUsers;
    users.sort((a, b) => b.rssi.compareTo(a.rssi));
    return users;
  }

  /// Gets users filtered by proximity category.
  List<NearbyUser> getUsersByProximity(BleProximity proximity) {
    return allUsers.where((u) => u.proximity == proximity).toList();
  }

  /// Gets only currently active users (seen recently).
  List<NearbyUser> getActiveUsers() {
    return allUsers.where((u) => u.isCurrentlyNearby).toList();
  }

  /// Clears the entire cache.
  void clear() {
    // Log encounters for all users before clearing
    for (final user in _userCache.values) {
      final peakRssi = _peakRssi[user.userId] ?? user.rssi;
      final closestProximity =
          _closestProximity[user.userId] ?? user.proximity;
      onUserStale?.call(user, peakRssi, closestProximity);
    }

    _userCache.clear();
    _bleToUserIdMap.clear();
    _userIdToBleMap.clear();
    _peakRssi.clear();
    _closestProximity.clear();
    _emitUpdate();
  }

  /// Starts the periodic cleanup timer.
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cleanupStaleUsers(),
    );
  }

  /// Removes users that haven't been seen recently.
  void _cleanupStaleUsers() {
    final now = DateTime.now();
    final staleUserIds = <String>[];

    for (final user in _userCache.values) {
      if (now.difference(user.lastSeen) > staleThreshold) {
        staleUserIds.add(user.userId);
      }
    }

    for (final oderId in staleUserIds) {
      removeUser(userId);
    }
  }

  /// Checks if proximity A is closer than proximity B.
  bool _isCloser(BleProximity a, BleProximity b) {
    const order = [
      BleProximity.immediate,
      BleProximity.near,
      BleProximity.far,
      BleProximity.unknown,
    ];
    return order.indexOf(a) < order.indexOf(b);
  }

  /// Emits a cache update to listeners.
  void _emitUpdate() {
    _cacheUpdateController.add(getUsersSortedByProximity());
  }

  /// Disposes resources.
  void dispose() {
    _cleanupTimer?.cancel();
    _cacheUpdateController.close();
  }
}
