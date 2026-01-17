import 'package:equatable/equatable.dart';

/// Proximity level based on RSSI values.
enum BleProximity {
  /// Very close (RSSI > -50 dBm, ~0-1m)
  immediate,

  /// Close (RSSI -50 to -70 dBm, ~1-3m)
  near,

  /// Moderate distance (RSSI -70 to -85 dBm, ~3-10m)
  far,

  /// Weak signal (RSSI < -85 dBm, >10m)
  veryFar,

  /// Unknown signal (no valid RSSI)
  unknown;

  /// Gets the display name for this proximity level.
  String get displayName {
    switch (this) {
      case BleProximity.immediate:
        return 'Very close';
      case BleProximity.near:
        return 'Nearby';
      case BleProximity.far:
        return 'Far';
      case BleProximity.veryFar:
        return 'Very far';
      case BleProximity.unknown:
        return 'Unknown';
    }
  }

  /// Determines proximity from RSSI value.
  static BleProximity fromRssi(int rssi) {
    if (rssi == 0) return BleProximity.unknown;
    if (rssi > -50) return BleProximity.immediate;
    if (rssi > -70) return BleProximity.near;
    if (rssi > -85) return BleProximity.far;
    return BleProximity.veryFar;
  }
}

/// Entity representing a nearby user detected via BLE.
class NearbyUser extends Equatable {
  /// User's 7-character username (unique identifier for BLE).
  final String username;

  /// Firebase user ID (for routing to chat, etc.).
  final String? userId;

  /// User's display name from profile.
  final String? displayName;

  /// User's photo URL from profile.
  final String? photoUrl;

  /// User's bio from profile.
  final String? bio;

  /// Signal strength (RSSI) in dBm.
  final int rssi;

  /// Whether this user is already connected (friend).
  final bool isConnected;

  /// When this user was first discovered in current session.
  final DateTime firstSeen;

  /// When this user was last detected.
  final DateTime lastSeen;

  const NearbyUser({
    required this.username,
    this.userId,
    this.displayName,
    this.photoUrl,
    this.bio,
    required this.rssi,
    this.isConnected = false,
    required this.firstSeen,
    required this.lastSeen,
  });

  /// Proximity based on RSSI.
  BleProximity get proximity => BleProximity.fromRssi(rssi);

  /// Estimated distance in meters (rough approximation).
  double get estimatedDistance {
    // Simple log-distance path loss model
    // Reference: RSSI at 1m is typically around -59 dBm
    const int referenceRssi = -59;
    const double pathLossExponent = 2.0;

    if (rssi >= 0) return 0.1;

    final ratio = (referenceRssi - rssi) / (10 * pathLossExponent);
    return (ratio > 0) ? 1.0 * (10.0 * ratio / 10).clamp(0.1, 100.0) : 0.5;
  }

  /// Whether this user was seen recently (within 10 seconds).
  bool get isCurrentlyNearby {
    final now = DateTime.now();
    return now.difference(lastSeen).inSeconds <= 10;
  }

  /// Creates a copy with updated fields.
  NearbyUser copyWith({
    String? username,
    String? userId,
    String? displayName,
    String? photoUrl,
    String? bio,
    int? rssi,
    bool? isConnected,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) {
    return NearbyUser(
      username: username ?? this.username,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      rssi: rssi ?? this.rssi,
      isConnected: isConnected ?? this.isConnected,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [
        username,
        userId,
        displayName,
        photoUrl,
        bio,
        rssi,
        isConnected,
        firstSeen,
        lastSeen,
      ];

  @override
  String toString() {
    return 'NearbyUser(username: $username, displayName: $displayName, rssi: $rssi)';
  }
}
