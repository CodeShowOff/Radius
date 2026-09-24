import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/user_location.dart';
import 'models/user_location_model.dart';

/// Service for managing user locations for nearby help feature.
///
/// Handles:
/// - Saving home/work locations
/// - Updating location preferences
/// - Managing opt-in/opt-out for help alerts
class UserLocationService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  UserLocationService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  // ==================== LOCATION MANAGEMENT ====================

  /// Saves or updates a user location (home or work).
  /// Also ensures nearbyHelpSettings exists with defaults so Firebase Functions
  /// can properly query users for nearby help notifications.
  Future<void> saveLocation({
    required String userId,
    required LocationType type,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      final locationModel = UserLocationModel(
        userId: userId,
        type: type,
        latitude: latitude,
        longitude: longitude,
        address: address,
        updatedAt: DateTime.now(),
        isActive: true,
        geoHash: _generateGeoHash(latitude, longitude),
      );

      // Use a batch to ensure both operations succeed together
      final batch = _firestore.batch();

      // Save the location
      final locationRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('locations')
          .doc(type.value);
      batch.set(locationRef, locationModel.toFirestore());

      // CRITICAL FIX: Ensure nearbyHelpSettings exists in the user document.
      // This ensures Firebase Functions can find this user when querying for
      // nearby help notifications. Without this, users who never opened the
      // settings page would have no nearbyHelpSettings field, and the Firebase
      // query could miss them.
      final userRef = _firestore.collection('users').doc(userId);
      batch.set(
        userRef,
        {
          'nearbyHelpSettings': {
            'receiveHelpAlerts': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      _logger.i('Saved ${type.value} location for user $userId with help settings');
    } catch (e, stack) {
      _logger.e('Error saving location', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets a specific location for a user.
  Future<UserLocation?> getLocation(String userId, LocationType type) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('locations')
          .doc(type.value)
          .get();

      if (!doc.exists) return null;
      return UserLocationModel.fromFirestore(doc);
    } catch (e, stack) {
      _logger.e('Error getting location', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Gets all saved locations for a user.
  Future<List<UserLocation>> getLocations(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('locations')
          .get();

      return snapshot.docs
          .map((doc) => UserLocationModel.fromFirestore(doc))
          .toList();
    } catch (e, stack) {
      _logger.e('Error getting locations', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Streams all locations for a user.
  Stream<List<UserLocation>> streamLocations(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('locations')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserLocationModel.fromFirestore(doc))
            .toList());
  }

  /// Deletes a saved location.
  Future<void> deleteLocation(String userId, LocationType type) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('locations')
          .doc(type.value)
          .delete();

      _logger.i('Deleted ${type.value} location for user $userId');
    } catch (e, stack) {
      _logger.e('Error deleting location', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Toggles the active status of a location.
  Future<void> toggleLocationActive(
    String userId,
    LocationType type,
    bool isActive,
  ) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('locations')
          .doc(type.value)
          .update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _logger.i('Toggled ${type.value} location active=$isActive for user $userId');
    } catch (e, stack) {
      _logger.e('Error toggling location', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== HELP ALERT SETTINGS ====================

  /// Gets the nearby help settings for a user.
  Future<NearbyHelpSettings> getHelpSettings(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();

      if (!doc.exists) {
        return NearbyHelpSettings(
          userId: userId,
          receiveHelpAlerts: true,
          updatedAt: DateTime.now(),
        );
      }

      final data = doc.data();
      final settingsData = data?['nearbyHelpSettings'] as Map<String, dynamic>?;

      return NearbyHelpSettingsModel.fromFirestore(userId, settingsData);
    } catch (e, stack) {
      _logger.e('Error getting help settings', error: e, stackTrace: stack);
      return NearbyHelpSettings(
        userId: userId,
        receiveHelpAlerts: true,
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Streams the nearby help settings for a user.
  Stream<NearbyHelpSettings> streamHelpSettings(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) {
        return NearbyHelpSettings(
          userId: userId,
          receiveHelpAlerts: true,
          updatedAt: DateTime.now(),
        );
      }

      final data = doc.data();
      final settingsData = data?['nearbyHelpSettings'] as Map<String, dynamic>?;

      return NearbyHelpSettingsModel.fromFirestore(userId, settingsData);
    });
  }

  /// Updates the nearby help settings for a user.
  Future<void> updateHelpSettings({
    required String userId,
    required bool receiveHelpAlerts,
  }) async {
    try {
      final settings = NearbyHelpSettingsModel(
        userId: userId,
        receiveHelpAlerts: receiveHelpAlerts,
        updatedAt: DateTime.now(),
      );

      await _firestore.collection('users').doc(userId).set({
        'nearbyHelpSettings': settings.toFirestore(),
      }, SetOptions(merge: true));

      _logger.i('Updated help settings for user $userId: receiveHelpAlerts=$receiveHelpAlerts');
    } catch (e, stack) {
      _logger.e('Error updating help settings', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== HELPER METHODS ====================

  /// Generates a simple geohash for the given coordinates.
  String _generateGeoHash(double latitude, double longitude) {
    final latPart = ((latitude + 90) * 1000).toInt().toString().padLeft(6, '0');
    final lonPart = ((longitude + 180) * 1000).toInt().toString().padLeft(6, '0');
    return '$latPart$lonPart';
  }
}
