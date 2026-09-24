import 'package:equatable/equatable.dart';

/// Represents a member's presence in a nearby group.
///
/// Members are automatically added/removed based on Bluetooth discovery
/// by the group creator's device.
class NearbyGroupMember extends Equatable {
  /// User ID of the member
  final String id;

  /// User's username (7-char BLE username)
  final String username;

  /// User's display name
  final String? displayName;

  /// User's photo URL
  final String? photoUrl;

  /// Signal strength when discovered
  final int rssi;

  /// When the member was first detected in this group
  final DateTime joinedAt;

  /// When the member was last detected
  final DateTime lastSeenAt;

  const NearbyGroupMember({
    required this.id,
    required this.username,
    this.displayName,
    this.photoUrl,
    required this.rssi,
    required this.joinedAt,
    required this.lastSeenAt,
  });

  /// Whether this member was seen recently (within 10 seconds)
  bool get isCurrentlyPresent {
    final now = DateTime.now();
    return now.difference(lastSeenAt).inSeconds <= 10;
  }

  /// Creates a copy with updated fields
  NearbyGroupMember copyWith({
    String? id,
    String? username,
    String? displayName,
    String? photoUrl,
    int? rssi,
    DateTime? joinedAt,
    DateTime? lastSeenAt,
  }) {
    return NearbyGroupMember(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      rssi: rssi ?? this.rssi,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        username,
        displayName,
        photoUrl,
        rssi,
        joinedAt,
        lastSeenAt,
      ];

  @override
  String toString() {
    return 'NearbyGroupMember(id: $id, username: $username, displayName: $displayName)';
  }
}
