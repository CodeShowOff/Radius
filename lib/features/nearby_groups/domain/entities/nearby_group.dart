import 'package:equatable/equatable.dart';

/// Status of a nearby group.
enum NearbyGroupStatus {
  /// Group is active and the creator is scanning
  active,

  /// Group is inactive (creator stopped scanning)
  inactive,
}

/// Entity representing a Bluetooth-based nearby group.
///
/// These groups are:
/// - Manually created by users
/// - Presence controlled by Bluetooth scanning (creator scans for nearby users)
/// - Temporary by proximity (not time-based)
/// - Discoverable via internet in real-time
class NearbyGroup extends Equatable {
  /// Unique identifier for the group
  final String id;

  /// Group name (topic for discussion)
  final String name;

  /// Optional description
  final String? description;

  /// User ID of the group creator
  final String creatorId;

  /// Creator's username (7-char BLE username)
  final String creatorUsername;

  /// Creator's display name
  final String? creatorDisplayName;

  /// Creator's photo URL
  final String? creatorPhotoUrl;

  /// Group status
  final NearbyGroupStatus status;

  /// Number of currently present members (including creator)
  final int memberCount;

  /// When the group was created
  final DateTime createdAt;

  /// When the group was last active (last scan update)
  final DateTime lastActiveAt;

  /// Preview of last message in group chat
  final String? lastMessagePreview;

  /// When the last message was sent
  final DateTime? lastMessageAt;

  const NearbyGroup({
    required this.id,
    required this.name,
    this.description,
    required this.creatorId,
    required this.creatorUsername,
    this.creatorDisplayName,
    this.creatorPhotoUrl,
    required this.status,
    required this.memberCount,
    required this.createdAt,
    required this.lastActiveAt,
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  /// Helper to check if group is active
  bool get isActive => status == NearbyGroupStatus.active;

  /// Helper to check if group has recent activity (within last 15 seconds)
  bool get isRecentlyActive {
    final now = DateTime.now();
    return now.difference(lastActiveAt).inSeconds <= 15;
  }

  /// Creates a copy with updated fields
  NearbyGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? creatorId,
    String? creatorUsername,
    String? creatorDisplayName,
    String? creatorPhotoUrl,
    NearbyGroupStatus? status,
    int? memberCount,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
  }) {
    return NearbyGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      creatorDisplayName: creatorDisplayName ?? this.creatorDisplayName,
      creatorPhotoUrl: creatorPhotoUrl ?? this.creatorPhotoUrl,
      status: status ?? this.status,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        creatorId,
        creatorUsername,
        creatorDisplayName,
        creatorPhotoUrl,
        status,
        memberCount,
        createdAt,
        lastActiveAt,
        lastMessagePreview,
        lastMessageAt,
      ];

  @override
  String toString() {
    return 'NearbyGroup(id: $id, name: $name, creatorId: $creatorId, status: $status, memberCount: $memberCount)';
  }
}
