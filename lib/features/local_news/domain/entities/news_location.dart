import 'package:equatable/equatable.dart';

/// How the user's location was determined.
enum LocationSource {
  /// Location entered manually by the user.
  manual,
}

/// Domain entity representing a resolved geographic location
/// for the local news feature.
class NewsLocation extends Equatable {
  /// Latitude coordinate.
  final double latitude;

  /// Longitude coordinate.
  final double longitude;

  /// District / sub-administrative area (from GPS geocoding).
  final String district;

  /// City name.
  final String city;

  /// Locality / sub-locality / neighborhood (finer-grained area).
  final String locality;

  /// Country name.
  final String country;

  /// How this location was obtained.
  final LocationSource source;

  const NewsLocation({
    required this.latitude,
    required this.longitude,
    required this.district,
    required this.city,
    required this.locality,
    required this.country,
    required this.source,
  });

  /// Human-readable location string for display.
  String get displayString {
    if (city.isNotEmpty && country.isNotEmpty) {
      return '$city, $country';
    }
    if (city.isNotEmpty) return city;
    return country;
  }

  /// Short label for headers.
  String get shortDisplayString {
    if (city.isNotEmpty) return '$city, $country';
    return country;
  }

  NewsLocation copyWith({
    double? latitude,
    double? longitude,
    String? district,
    String? city,
    String? locality,
    String? country,
    LocationSource? source,
  }) {
    return NewsLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      district: district ?? this.district,
      city: city ?? this.city,
      locality: locality ?? this.locality,
      country: country ?? this.country,
      source: source ?? this.source,
    );
  }

  @override
  List<Object?> get props => [
        latitude,
        longitude,
        district,
        city,
        locality,
        country,
        source,
      ];
}
