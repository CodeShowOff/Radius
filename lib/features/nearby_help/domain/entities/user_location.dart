import 'package:equatable/equatable.dart';

/// Type of saved location.
enum LocationType {
  home,
  work,
}

extension LocationTypeX on LocationType {
  String get value {
    switch (this) {
      case LocationType.home:
        return 'home';
      case LocationType.work:
        return 'work';
    }
  }

  String get displayName {
    switch (this) {
      case LocationType.home:
        return 'Home';
      case LocationType.work:
        return 'Work';
    }
  }

  static LocationType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'home':
        return LocationType.home;
      case 'work':
        return LocationType.work;
      default:
        return LocationType.home;
    }
  }
}

/// Domain entity representing a user's saved location.
///
/// Users can save their home and work locations for receiving
/// nearby help notifications when they're at these locations.
class UserLocation extends Equatable {
  /// User ID who owns this location.
  final String userId;

  /// Type of location (home/work).
  final LocationType type;

  /// Latitude of the location.
  final double latitude;

  /// Longitude of the location.
  final double longitude;

  /// Human-readable address (optional, for display purposes).
  final String? address;

  /// When the location was last updated.
  final DateTime updatedAt;

  /// Whether this location is active for receiving help alerts.
  final bool isActive;

  const UserLocation({
    required this.userId,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.updatedAt,
    this.isActive = true,
  });

  /// Creates a copy with updated fields.
  UserLocation copyWith({
    String? userId,
    LocationType? type,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return UserLocation(
      userId: userId ?? this.userId,
      type: type ?? this.type,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        type,
        latitude,
        longitude,
        address,
        updatedAt,
        isActive,
      ];
}

/// Settings for receiving nearby help alerts.
class NearbyHelpSettings extends Equatable {
  /// User ID.
  final String userId;

  /// Whether the user wants to receive help alerts.
  final bool receiveHelpAlerts;

  /// When settings were last updated.
  final DateTime updatedAt;

  const NearbyHelpSettings({
    required this.userId,
    this.receiveHelpAlerts = true,
    required this.updatedAt,
  });

  NearbyHelpSettings copyWith({
    String? userId,
    bool? receiveHelpAlerts,
    DateTime? updatedAt,
  }) {
    return NearbyHelpSettings(
      userId: userId ?? this.userId,
      receiveHelpAlerts: receiveHelpAlerts ?? this.receiveHelpAlerts,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [userId, receiveHelpAlerts, updatedAt];
}
