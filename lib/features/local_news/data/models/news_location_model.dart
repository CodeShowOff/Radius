import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/news_location.dart';

/// Firestore serialization for NewsLocation entity.
///
/// Used for the `localNewsLocation` field on `users/{userId}`.
class NewsLocationModel extends NewsLocation {
  const NewsLocationModel({
    required super.latitude,
    required super.longitude,
    required super.district,
    required super.city,
    required super.locality,
    required super.country,
    required super.source,
  });

  /// Creates model from a Firestore map (the `localNewsLocation` sub-field).
  ///
  /// Returns `null` if the data is missing required fields.
  static NewsLocationModel? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;

    final latitude = data['latitude'] as num?;
    final longitude = data['longitude'] as num?;
    final district = data['district'] as String? ?? '';
    final city = data['city'] as String?;

    if (latitude == null || longitude == null ||
        city == null || city.isEmpty) {
      return null;
    }

    return NewsLocationModel(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      district: district,
      city: city,
      locality: data['locality'] as String? ?? '',
      country: data['country'] as String? ?? '',
      source: _parseSource(data['source'] as String?),
    );
  }

  /// Creates model from domain entity.
  factory NewsLocationModel.fromEntity(NewsLocation location) {
    return NewsLocationModel(
      latitude: location.latitude,
      longitude: location.longitude,
      district: location.district,
      city: location.city,
      locality: location.locality,
      country: location.country,
      source: location.source,
    );
  }

  /// Converts to Firestore map for storage as a sub-field.
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'district': district,
      'city': city,
      'locality': locality,
      'country': country,
      'source': source.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Converts to domain entity.
  NewsLocation toEntity() {
    return NewsLocation(
      latitude: latitude,
      longitude: longitude,
      district: district,
      city: city,
      locality: locality,
      country: country,
      source: source,
    );
  }

  static LocationSource _parseSource(String? value) {
    if (value == 'manual') return LocationSource.manual;
    return LocationSource.manual;
  }
}
