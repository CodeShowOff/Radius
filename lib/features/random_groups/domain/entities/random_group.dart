import 'package:equatable/equatable.dart';

/// Status of a random group.
enum RandomGroupStatus {
  /// Group is active and accepting join requests
  active,

  /// Group is inactive/deleted
  inactive,
}

/// Entity representing an internet-based random group.
///
/// These groups are:
/// - Manually created by users
/// - Not location-based (internet-only)
/// - Discoverable by all users
/// - Require admin approval to join
class RandomGroup extends Equatable {
  /// Unique identifier for the group
  final String id;

  /// Group name
  final String name;

  /// Optional topic or category
  final String? topic;

  /// Optional description / rules
  final String? description;

  /// User ID of the group creator (Primary Admin)
  final String creatorId;

  /// Creator's username
  final String creatorUsername;

  /// Creator's display name
  final String? creatorDisplayName;

  /// Creator's photo URL
  final String? creatorPhotoUrl;

  /// Group's profile photo URL
  final String? photoUrl;

  /// List of admin user IDs (includes creator)
  final List<String> adminIds;

  /// Group status
  final RandomGroupStatus status;

  /// Number of approved members
  final int memberCount;

  /// Number of pending join requests
  final int pendingRequestCount;

  /// When the group was created
  final DateTime createdAt;

  /// When the group was last active
  final DateTime lastActiveAt;

  /// Preview of last message in group chat
  final String? lastMessagePreview;

  /// When the last message was sent
  final DateTime? lastMessageAt;

  const RandomGroup({
    required this.id,
    required this.name,
    this.topic,
    this.description,
    required this.creatorId,
    required this.creatorUsername,
    this.creatorDisplayName,
    this.creatorPhotoUrl,
    this.photoUrl,
    required this.adminIds,
    required this.status,
    required this.memberCount,
    this.pendingRequestCount = 0,
    required this.createdAt,
    required this.lastActiveAt,
    this.lastMessagePreview,
    this.lastMessageAt,
  });

  /// Helper to check if group is active
  bool get isActive => status == RandomGroupStatus.active;

  /// Check if a user is an admin
  bool isAdmin(String userId) => adminIds.contains(userId);

  /// Check if a user is the creator
  bool isCreator(String userId) => creatorId == userId;

  /// Creates a copy with updated fields
  RandomGroup copyWith({
    String? id,
    String? name,
    String? topic,
    String? description,
    String? creatorId,
    String? creatorUsername,
    String? creatorDisplayName,
    String? creatorPhotoUrl,
    String? photoUrl,
    List<String>? adminIds,
    RandomGroupStatus? status,
    int? memberCount,
    int? pendingRequestCount,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
  }) {
    return RandomGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      topic: topic ?? this.topic,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      creatorDisplayName: creatorDisplayName ?? this.creatorDisplayName,
      creatorPhotoUrl: creatorPhotoUrl ?? this.creatorPhotoUrl,
      photoUrl: photoUrl ?? this.photoUrl,
      adminIds: adminIds ?? this.adminIds,
      status: status ?? this.status,
      memberCount: memberCount ?? this.memberCount,
      pendingRequestCount: pendingRequestCount ?? this.pendingRequestCount,
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
        topic,
        description,
        creatorId,
        creatorUsername,
        creatorDisplayName,
        creatorPhotoUrl,
        photoUrl,
        adminIds,
        status,
        memberCount,
        pendingRequestCount,
        createdAt,
        lastActiveAt,
        lastMessagePreview,
        lastMessageAt,
      ];
}
