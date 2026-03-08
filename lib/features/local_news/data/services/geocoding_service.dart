import 'package:geocoding/geocoding.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/news_location.dart';

/// Service for converting GPS coordinates into human-readable location names.
///
/// Uses the `geocoding` package which relies on platform-native geocoding
/// (Android Geocoder / iOS CLGeocoder) — no API key required.
class GeocodingService {
  final Logger _logger;

  GeocodingService({Logger? logger}) : _logger = logger ?? Logger();

  /// Reverse-geocodes [latitude] and [longitude] into a [NewsLocation].
  ///
  /// Maps platform `Placemark` fields:
  /// - `subAdministrativeArea` → district
  /// - `locality` → city
  /// - `subLocality` → locality (neighborhood / area)
  /// - `country` → country
  ///
  /// Falls back to adjacent fields when a primary field is empty.
  /// Throws [GeocodingException] if no placemarks are returned.
  Future<NewsLocation> reverseGeocode({
    required double latitude,
    required double longitude,
    required LocationSource source,
  }) async {
    try {
      _logger.d('Reverse geocoding: ($latitude, $longitude)');

      final placemarks = await placemarkFromCoordinates(latitude, longitude);

      if (placemarks.isEmpty) {
        throw GeocodingException('No placemarks found for ($latitude, $longitude)');
      }

      final placemark = placemarks.first;

      final district = _resolveDistrict(placemark);
      final city = _resolveCity(placemark);
      final locality = _resolveLocality(placemark);
      final country = placemark.country ?? '';

      _logger.i(
        'Geocoded ($latitude, $longitude) → '
        'district=$district, city=$city, locality=$locality, country=$country',
      );

      return NewsLocation(
        latitude: latitude,
        longitude: longitude,
        district: district,
        city: city,
        locality: locality,
        country: country,
        source: source,
      );
    } on GeocodingException {
      rethrow;
    } catch (e, stack) {
      _logger.e('Reverse geocoding failed', error: e, stackTrace: stack);
      throw GeocodingException(
        'Failed to determine location from coordinates: $e',
      );
    }
  }

  /// Resolves district from placemark with fallbacks.
  ///
  /// Priority: subAdministrativeArea → administrativeArea
  String _resolveDistrict(Placemark placemark) {
    final sub = placemark.subAdministrativeArea;
    if (sub != null && sub.isNotEmpty) return sub;

    final admin = placemark.administrativeArea;
    if (admin != null && admin.isNotEmpty) return admin;

    return '';
  }

  /// Resolves city from placemark with fallbacks.
  ///
  /// Priority: locality → subAdministrativeArea → administrativeArea
  String _resolveCity(Placemark placemark) {
    final loc = placemark.locality;
    if (loc != null && loc.isNotEmpty) return loc;

    final sub = placemark.subAdministrativeArea;
    if (sub != null && sub.isNotEmpty) return sub;

    final admin = placemark.administrativeArea;
    if (admin != null && admin.isNotEmpty) return admin;

    return '';
  }

  /// Resolves locality/neighborhood from placemark with fallbacks.
  ///
  /// Priority: subLocality → thoroughfare → locality
  String _resolveLocality(Placemark placemark) {
    final subLoc = placemark.subLocality;
    if (subLoc != null && subLoc.isNotEmpty) return subLoc;

    final thoroughfare = placemark.thoroughfare;
    if (thoroughfare != null && thoroughfare.isNotEmpty) return thoroughfare;

    // Fall back to city-level locality if nothing finer exists
    final loc = placemark.locality;
    if (loc != null && loc.isNotEmpty) return loc;

    return '';
  }
}

/// Exception thrown when geocoding fails.
class GeocodingException implements Exception {
  final String message;

  const GeocodingException(this.message);

  @override
  String toString() => 'GeocodingException: $message';
}
