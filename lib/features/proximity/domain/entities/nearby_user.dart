import 'package:equatable/equatable.dart';

import '../../../../core/services/bluetooth/ble_device.dart';

/// Proximity level categories for UI display.
enum ProximityLevel {
  close, // < 3 meters
  medium, // 3-7 meters
  far, // 7-10 meters
}

/// Entity representing a nearby user detected via BLE.
class NearbyUser extends Equatable {
  /// Firebase user ID.
  final String userId;

  /// User's display name.
  final String? displayName;

  /// User's profile photo URL.
  final String? photoUrl;

  /// User's bio.
  final String? bio;

  /// The BLE anonymous ID currently being broadcast.
  final String bleAnonymousId;

  /// Signal strength (RSSI).
  final int rssi;

  /// Calculated proximity category.
  final BleProximity proximity;

  /// Estimated distance in meters.
  final double estimatedDistance;

  /// When this user was first discovered in current session.
  final DateTime firstSeen;

  /// When this user was last detected.
  final DateTime lastSeen;

  /// Number of times this user has been detected.
  final int encounterCount;

  /// Whether this user is currently visible (profile visibility setting).
  final bool isVisible;

  /// Whether we've already connected with this user.
  final bool isConnected;

  const NearbyUser({
    required this.userId,
    this.displayName,
    this.photoUrl,
    this.bio,
    required this.bleAnonymousId,
    required this.rssi,
    required this.proximity,
    required this.estimatedDistance,
    required this.firstSeen,
    required this.lastSeen,
    this.encounterCount = 1,
    this.isVisible = true,
    this.isConnected = false,
  });

  /// Returns proximity level based on distance (for UI).
  ProximityLevel get proximityLevel {
    if (estimatedDistance < 3) return ProximityLevel.close;
    if (estimatedDistance < 7) return ProximityLevel.medium;
    return ProximityLevel.far;
  }

  /// Creates a copy with updated fields.
  /// Use explicit null values wrapped in [Optional] to clear nullable fields:
  /// - Pass the value directly to keep or update
  /// - Pass [clearDisplayName], [clearPhotoUrl], [clearBio] as true to set to null
  NearbyUser copyWith({
    String? userId,
    String? displayName,
    bool clearDisplayName = false,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? bio,
    bool clearBio = false,
    String? bleAnonymousId,
    int? rssi,
    BleProximity? proximity,
    double? estimatedDistance,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int? encounterCount,
    bool? isVisible,
    bool? isConnected,
  }) {
    return NearbyUser(
      userId: userId ?? this.userId,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      bio: clearBio ? null : (bio ?? this.bio),
      bleAnonymousId: bleAnonymousId ?? this.bleAnonymousId,
      rssi: rssi ?? this.rssi,
      proximity: proximity ?? this.proximity,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      encounterCount: encounterCount ?? this.encounterCount,
      isVisible: isVisible ?? this.isVisible,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  /// Updates with new BLE detection data.
  NearbyUser updateWithDetection({
    required String bleAnonymousId,
    required int rssi,
    required BleProximity proximity,
    required double estimatedDistance,
  }) {
    return copyWith(
      bleAnonymousId: bleAnonymousId,
      rssi: rssi,
      proximity: proximity,
      estimatedDistance: estimatedDistance,
      lastSeen: DateTime.now(),
      encounterCount: encounterCount + 1,
    );
  }

  /// Duration since first seen.
  Duration get timeNearby => lastSeen.difference(firstSeen);

  /// Whether user was seen recently (within 30 seconds).
  bool get isCurrentlyNearby {
    return DateTime.now().difference(lastSeen).inSeconds < 30;
  }

  @override
  List<Object?> get props => [
        userId,
        displayName,
        photoUrl,
        bio,
        bleAnonymousId,
        rssi,
        proximity,
        estimatedDistance,
        firstSeen,
        lastSeen,
        encounterCount,
        isVisible,
        isConnected,
      ];

  @override
  String toString() {
    return 'NearbyUser(userId: $userId, name: $displayName, proximity: ${proximity.displayName})';
  }
}

/// Encounter record for Firestore persistence.
class Encounter extends Equatable {
  final String userId;
  final String otherUserId;
  final DateTime timestamp;
  final int durationSeconds;
  final String closestProximity;
  final int peakRssi;
  final bool wasConnected;

  const Encounter({
    required this.userId,
    required this.otherUserId,
    required this.timestamp,
    required this.durationSeconds,
    required this.closestProximity,
    required this.peakRssi,
    this.wasConnected = false,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'otherUserId': otherUserId,
      'timestamp': timestamp.toIso8601String(),
      'durationSeconds': durationSeconds,
      'closestProximity': closestProximity,
      'peakRssi': peakRssi,
      'wasConnected': wasConnected,
    };
  }

  factory Encounter.fromFirestore(Map<String, dynamic> data) {
    // Validate required fields
    final userId = data['userId'];
    final otherUserId = data['otherUserId'];
    final timestamp = data['timestamp'];
    final durationSeconds = data['durationSeconds'];
    final closestProximity = data['closestProximity'];
    final peakRssi = data['peakRssi'];

    if (userId is! String || userId.isEmpty) {
      throw ArgumentError('Invalid or missing userId in Encounter data');
    }
    if (otherUserId is! String || otherUserId.isEmpty) {
      throw ArgumentError('Invalid or missing otherUserId in Encounter data');
    }
    if (timestamp is! String) {
      throw ArgumentError('Invalid or missing timestamp in Encounter data');
    }
    if (durationSeconds is! int) {
      throw ArgumentError(
          'Invalid or missing durationSeconds in Encounter data');
    }
    if (closestProximity is! String) {
      throw ArgumentError(
          'Invalid or missing closestProximity in Encounter data');
    }
    if (peakRssi is! int) {
      throw ArgumentError('Invalid or missing peakRssi in Encounter data');
    }

    return Encounter(
      userId: userId,
      otherUserId: otherUserId,
      timestamp: DateTime.parse(timestamp),
      durationSeconds: durationSeconds,
      closestProximity: closestProximity,
      peakRssi: peakRssi,
      wasConnected: data['wasConnected'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        otherUserId,
        timestamp,
        durationSeconds,
        closestProximity,
        peakRssi,
        wasConnected,
      ];
}
