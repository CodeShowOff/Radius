import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

import '../../../location_groups/data/location_data_service.dart';
import '../../domain/entities/news_location.dart';
import 'geocoding_service.dart';

/// Service for managing user location in the local news feature.
///
/// Handles:
/// - GPS location detection with permission management
/// - Reverse geocoding via [GeocodingService]
/// - Persisting and reading the user's preferred news location
///
/// Firestore path: `users/{userId}` field `localNewsLocation`.
class NewsLocationService {
  final FirebaseFirestore _firestore;
  final GeocodingService _geocodingService;
  final LocationDataService _locationDataService;
  final Logger _logger;

  NewsLocationService({
    FirebaseFirestore? firestore,
    required GeocodingService geocodingService,
    LocationDataService? locationDataService,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _geocodingService = geocodingService,
        _locationDataService = locationDataService ?? LocationDataService(),
        _logger = logger ?? Logger();

  // ==================== GPS LOCATION ====================

  /// Gets the current GPS position after handling permissions.
  ///
  /// Throws [LocationServiceException] if location services are disabled
  /// or permissions are denied.
  Future<Position> getCurrentGpsPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceException(
        'Location services are disabled. Please enable them in settings.',
        reason: LocationFailureReason.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationServiceException(
          'Location permission denied. Please grant location access.',
          reason: LocationFailureReason.permissionDenied,
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationServiceException(
        'Location permission is permanently denied. '
        'Please enable it from app settings.',
        reason: LocationFailureReason.permissionDeniedForever,
      );
    }

    _logger.d('Getting current GPS position...');

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

    _logger.i('GPS position: (${position.latitude}, ${position.longitude})');
    return position;
  }

  // ==================== RESOLVE LOCATION ====================

  /// Gets the current GPS location, reverse-geocodes it, and matches the
  /// city against the bundled locations.json data.
  ///
  /// Returns a [NewsLocation] whose [city] and [country] are canonical names
  /// from locations.json when a match is found.
  /// Throws [LocationCityMatchException] if the GPS city cannot be matched.
  Future<NewsLocation> detectCurrentLocation() async {
    final position = await getCurrentGpsPosition();
    final raw = await _geocodingService.reverseGeocode(
      latitude: position.latitude,
      longitude: position.longitude,
      source: LocationSource.gps,
    );

    // Match against locations.json
    await _locationDataService.ensureLoaded();

    final matchedCountry =
        _locationDataService.findMatchingCountry(raw.country);
    if (matchedCountry == null) {
      _logger.w('Country not found in locations.json: ${raw.country}');
      throw LocationCityMatchException(
        'Could not match your country "${raw.country}" in the location database. '
        'Please select your location manually.',
        detectedCity: raw.city,
        detectedCountry: raw.country,
      );
    }

    final matchedCity =
        _locationDataService.findMatchingCity(matchedCountry, raw.city);
    if (matchedCity == null) {
      _logger.w(
        'City not found in locations.json: ${raw.city} ($matchedCountry)',
      );
      throw LocationCityMatchException(
        'Could not match city "${raw.city}" in $matchedCountry. '
        'Please select your location manually.',
        detectedCity: raw.city,
        detectedCountry: matchedCountry,
      );
    }

    _logger.i('GPS matched to: $matchedCity, $matchedCountry');
    return raw.copyWith(city: matchedCity, country: matchedCountry);
  }

  /// Reverse-geocodes arbitrary coordinates into a [NewsLocation].
  Future<NewsLocation> resolveLocation({
    required double latitude,
    required double longitude,
    required LocationSource source,
  }) async {
    return _geocodingService.reverseGeocode(
      latitude: latitude,
      longitude: longitude,
      source: source,
    );
  }

  // ==================== PERSISTENCE ====================

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
    if (value == 'gps') return LocationSource.gps;
    if (value == 'manual') return LocationSource.manual;
    return LocationSource.gps;
  }
}

/// Reason why location acquisition failed.
enum LocationFailureReason {
  /// Device location services (GPS) are turned off.
  serviceDisabled,

  /// User denied the location permission prompt.
  permissionDenied,

  /// User permanently denied location permission.
  permissionDeniedForever,
}

/// Exception thrown when location services or permissions are unavailable.
class LocationServiceException implements Exception {
  final String message;
  final LocationFailureReason reason;

  const LocationServiceException(
    this.message, {
    this.reason = LocationFailureReason.serviceDisabled,
  });

  @override
  String toString() => 'LocationServiceException: $message';
}

/// Exception thrown when GPS-detected city cannot be matched in locations.json.
class LocationCityMatchException implements Exception {
  final String message;
  final String detectedCity;
  final String detectedCountry;

  const LocationCityMatchException(
    this.message, {
    required this.detectedCity,
    required this.detectedCountry,
  });

  @override
  String toString() => 'LocationCityMatchException: $message';
}
