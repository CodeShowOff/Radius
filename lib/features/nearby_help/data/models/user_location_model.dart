import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/user_location.dart';

/// Firestore model for UserLocation entity.
///
/// Firestore Schema:
/// ```
/// users/{userId}/locations/{locationType}
///   - userId: string
///   - type: string ('home' | 'work')
///   - latitude: number
///   - longitude: number
///   - address: string?
///   - updatedAt: timestamp
///   - isActive: boolean
///   - geoHash: string (for geospatial queries)
/// ```
class UserLocationModel extends UserLocation {
  /// GeoHash for efficient geospatial queries.
  final String? geoHash;

  const UserLocationModel({
    required super.userId,
    required super.type,
    required super.latitude,
    required super.longitude,
    super.address,
    required super.updatedAt,
    super.isActive = true,
    this.geoHash,
  });

  /// Creates model from Firestore document.
  factory UserLocationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return UserLocationModel(
      userId: data['userId'] as String,
      type: LocationTypeX.fromString(data['type'] as String? ?? 'home'),
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      address: data['address'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: data['isActive'] as bool? ?? true,
      geoHash: data['geoHash'] as String?,
    );
  }

  /// Creates model from UserLocation entity.
  factory UserLocationModel.fromEntity(UserLocation location, {String? geoHash}) {
    return UserLocationModel(
      userId: location.userId,
      type: location.type,
      latitude: location.latitude,
      longitude: location.longitude,
      address: location.address,
      updatedAt: location.updatedAt,
      isActive: location.isActive,
      geoHash: geoHash,
    );
  }

  /// Converts model to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'type': type.value,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'updatedAt': FieldValue.serverTimestamp(),
      'isActive': isActive,
      'geoHash': geoHash,
    };
  }
}

/// Firestore model for NearbyHelpSettings.
///
/// Firestore Schema:
/// ```
/// users/{userId}
///   - nearbyHelpSettings:
///       - receiveHelpAlerts: boolean
///       - updatedAt: timestamp
/// ```
class NearbyHelpSettingsModel extends NearbyHelpSettings {
  const NearbyHelpSettingsModel({
    required super.userId,
    super.receiveHelpAlerts = true,
    required super.updatedAt,
  });

  /// Creates model from Firestore document.
  factory NearbyHelpSettingsModel.fromFirestore(String userId, Map<String, dynamic>? data) {
    if (data == null) {
      return NearbyHelpSettingsModel(
        userId: userId,
        receiveHelpAlerts: true,
        updatedAt: DateTime.now(),
      );
    }

    return NearbyHelpSettingsModel(
      userId: userId,
      receiveHelpAlerts: data['receiveHelpAlerts'] as bool? ?? true,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Creates model from NearbyHelpSettings entity.
  factory NearbyHelpSettingsModel.fromEntity(NearbyHelpSettings settings) {
    return NearbyHelpSettingsModel(
      userId: settings.userId,
      receiveHelpAlerts: settings.receiveHelpAlerts,
      updatedAt: settings.updatedAt,
    );
  }

  /// Converts model to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'receiveHelpAlerts': receiveHelpAlerts,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
