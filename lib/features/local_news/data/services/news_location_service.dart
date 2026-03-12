import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/news_location.dart';

/// Service for managing user location in the local news feature.
///
/// Handles persisting and reading the user's preferred news location.
///
/// Firestore path: `users/{userId}` field `localNewsLocation`.
class NewsLocationService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  NewsLocationService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  // ==================== PERSISTENCE ======================================

  /// Saves the user's selected news location to Firestore.
  ///
  /// Stored as a map field on `users/{userId}.localNewsLocation`.
  Future<void> saveUserNewsLocation({
    required String userId,
    required NewsLocation location,
  }) async {
    try {
      _logger.d('Saving news location for user $userId');

      await _firestore.collection('users').doc(userId).set(
        {
          'localNewsLocation': {
            'latitude': location.latitude,
            'longitude': location.longitude,
            'district': location.district,
            'city': location.city,
            'locality': location.locality,
            'country': location.country,
            'source': location.source.name,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );

      _logger.i('News location saved for user $userId: ${location.shortDisplayString}');
    } catch (e, stack) {
      _logger.e('Failed to save news location', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Reads the user's saved news location from Firestore.
  ///
  /// Returns `null` if the user hasn't set a news location yet.
  Future<NewsLocation?> getUserNewsLocation(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();

      if (data == null) return null;

      final locationData = data['localNewsLocation'] as Map<String, dynamic>?;
      if (locationData == null) return null;

      final latitude = locationData['latitude'] as num?;
      final longitude = locationData['longitude'] as num?;
      final district = locationData['district'] as String? ?? '';
      final city = locationData['city'] as String?;

      // Require at minimum coordinates + city
      if (latitude == null || longitude == null ||
          city == null || city.isEmpty) {
        return null;
      }

      return NewsLocation(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        district: district,
        city: city,
        locality: locationData['locality'] as String? ?? '',
        country: locationData['country'] as String? ?? '',
        source: _parseSource(locationData['source'] as String?),
      );
    } catch (e, stack) {
      _logger.e('Failed to read news location', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Clears the user's saved news location.
  Future<void> clearUserNewsLocation(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'localNewsLocation': FieldValue.delete(),
      });
      _logger.i('News location cleared for user $userId');
    } catch (e, stack) {
      _logger.e('Failed to clear news location', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== HELPERS ====================

  static LocationSource _parseSource(String? value) {
    if (value == 'manual') return LocationSource.manual;
    return LocationSource.manual;
  }
}
