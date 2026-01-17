import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/entities/nearby_user.dart';
import '../../../core/services/logging/device_log.dart';

/// Handles Firestore operations for proximity and encounters.
class ProximityFirestoreService {
  final FirebaseFirestore _firestore;

  /// Debounce timer for batched updates.
  Timer? _updateDebounceTimer;

  /// Pending updates to batch.
  final Map<String, Map<String, dynamic>> _pendingUpdates = {};

  /// Minimum time between Firestore writes (debounce).
  final Duration updateDebounce;

  /// Current user's ID.
  String? _currentUserId;

  ProximityFirestoreService({
    FirebaseFirestore? firestore,
    this.updateDebounce = const Duration(seconds: 5),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Sets the current user ID.
  void setCurrentUserId(String userId) {
    _currentUserId = userId;
  }

  // ============== BLE ID Mapping ==============

  /// Looks up a Firebase user ID by their BLE anonymous ID.
  /// Returns null if no user is found with that BLE ID.
  Future<Map<String, dynamic>?> lookupUserByBleId(String bleId) async {
    try {
      // Query users where bleIdentifier matches
      // Users store their current BLE ID in their user document
      final snapshot = await _firestore
          .collection('users')
          .where('bleIdentifier', isEqualTo: bleId)
          .where('isDiscoverable', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final data = doc.data();
      return {
        'userId': doc.id,
        'displayName': data['displayName'] ?? 'Unknown',
        'photoUrl': data['avatarUrl'],
        'bio': data['bio'],
        'isVisible': data['isDiscoverable'] ?? true,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProximityFirestoreService] lookupUserByBleId failed: $e');
      }
      DeviceLog.instance
          .warning('firestore', 'lookupUserByBleId failed', data: {
        'bleIdPrefix': bleId.length >= 8 ? bleId.substring(0, 8) : bleId,
        'error': e.toString(),
      });
      return null;
    }
  }

  /// Updates the current user's BLE identifier in Firestore.
  Future<void> updateCurrentUserBleId(String bleId) async {
    if (_currentUserId == null) return;

    try {
      await _firestore.collection('users').doc(_currentUserId).update({
        'bleIdentifier': bleId,
        'bleIdUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[ProximityFirestoreService] updateCurrentUserBleId failed: $e');
      }
      // Ignore errors - not critical
    }
  }

  // ============== Encounter Logging ==============

  /// Logs an encounter when a nearby user goes stale.
  Future<void> logEncounter(Encounter encounter) async {
    if (_currentUserId == null) return;
    if (encounter.durationSeconds < 10) return; // Ignore very brief encounters

    try {
      // Add to encounters collection
      await _firestore.collection('encounters').add(encounter.toFirestore());

      // Update encounter stats for both users
      await _updateEncounterStats(encounter.userId, encounter.otherUserId);
    } catch (e) {
      // Log error but don't throw
    }
  }

  /// Updates encounter statistics for users.
  Future<void> _updateEncounterStats(String userId1, String userId2) async {
    final batch = _firestore.batch();

    // Update user 1's stats
    final user1StatsRef = _firestore
        .collection('profiles')
        .doc(userId1)
        .collection('stats')
        .doc('encounters');

    batch.set(
      user1StatsRef,
      {
        'totalEncounters': FieldValue.increment(1),
        'lastEncounterAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // Update user 2's stats
    final user2StatsRef = _firestore
        .collection('profiles')
        .doc(userId2)
        .collection('stats')
        .doc('encounters');

    batch.set(
      user2StatsRef,
      {
        'totalEncounters': FieldValue.increment(1),
        'lastEncounterAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  // ============== Real-time Proximity ==============

  /// Updates the current user's "currently nearby" list.
  /// This is debounced to avoid excessive writes.
  void updateNearbyUsers(List<NearbyUser> nearbyUsers) {
    if (_currentUserId == null) return;

    // Prepare update data
    final nearbyData = nearbyUsers
        .where((u) => u.isCurrentlyNearby)
        .map((u) => {
              'userId': u.userId,
              'proximity': u.proximity.name,
              'lastSeen': u.lastSeen.toIso8601String(),
            })
        .toList();

    _pendingUpdates[_currentUserId!] = {
      'nearbyUsers': nearbyData,
      'nearbyCount': nearbyData.length,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    // Debounce the actual write
    _scheduleUpdate();
  }

  /// Schedules a debounced Firestore update.
  void _scheduleUpdate() {
    _updateDebounceTimer?.cancel();
    _updateDebounceTimer = Timer(updateDebounce, _flushPendingUpdates);
  }

  /// Flushes pending updates to Firestore.
  Future<void> _flushPendingUpdates() async {
    if (_pendingUpdates.isEmpty) return;

    final updates = Map<String, Map<String, dynamic>>.from(_pendingUpdates);
    _pendingUpdates.clear();

    try {
      final batch = _firestore.batch();

      for (final entry in updates.entries) {
        final docRef = _firestore
            .collection('profiles')
            .doc(entry.key)
            .collection('proximity')
            .doc('current');

        batch.set(docRef, entry.value, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      // Re-add failed updates for retry
      _pendingUpdates.addAll(updates);
    }
  }

  /// Clears the current user's nearby list (when stopping discovery).
  Future<void> clearNearbyUsers() async {
    if (_currentUserId == null) return;

    try {
      await _firestore
          .collection('profiles')
          .doc(_currentUserId)
          .collection('proximity')
          .doc('current')
          .delete();
    } catch (e) {
      // Ignore errors
    }
  }

  // ============== Queries ==============

  /// Gets encounter history for the current user.
  Future<List<Encounter>> getEncounterHistory({
    int limit = 50,
    DateTime? since,
  }) async {
    if (_currentUserId == null) return [];

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('encounters')
          .where('userId', isEqualTo: _currentUserId)
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (since != null) {
        query = query.where(
          'timestamp',
          isGreaterThan: since.toIso8601String(),
        );
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Encounter.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Streams the current user's encounter count.
  Stream<int> encounterCountStream() {
    if (_currentUserId == null) return Stream.value(0);

    return _firestore
        .collection('profiles')
        .doc(_currentUserId)
        .collection('stats')
        .doc('encounters')
        .snapshots()
        .map((doc) => doc.data()?['totalEncounters'] as int? ?? 0);
  }

  /// Checks if two users have encountered before.
  Future<bool> hasEncounteredBefore(String otherId) async {
    if (_currentUserId == null) return false;

    try {
      final snapshot = await _firestore
          .collection('encounters')
          .where('userId', isEqualTo: _currentUserId)
          .where('otherUserId', isEqualTo: otherId)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Disposes resources.
  void dispose() {
    _updateDebounceTimer?.cancel();
    _flushPendingUpdates(); // Flush any pending updates
  }
}
