import 'package:equatable/equatable.dart';

/// How the user's location was determined.
enum LocationSource {
  /// Location obtained via GPS.
  gps,

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

  /// District / sub-administrative area (primary feed grouping).
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
    if (locality.isNotEmpty && locality != district) {
      return '$locality, $district';
    }
    return '$district, $city';
  }

  /// Short label for headers.
  String get shortDisplayString => '$district, $city';

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
