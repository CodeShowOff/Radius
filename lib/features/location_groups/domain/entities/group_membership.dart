import 'package:equatable/equatable.dart';

/// Role of a user within a group.
enum GroupRole {
  /// Full admin privileges
  admin,

  /// Regular member
  member,
}

/// Membership status for a user in a group.
enum MembershipStatus {
  /// Currently active member
  active,

  /// Pending approval (for request-to-join groups)
  pending,

  /// User was banned from the group
  banned,

  /// User left the group voluntarily
  left,
}

/// Entity representing a user's membership in a location group.
class GroupMembership extends Equatable {
  /// Unique membership ID
  final String id;

  /// Group this membership belongs to
  final String groupId;

  /// User ID of the member
  final String userId;

  /// User's display name (denormalized)
  final String? userName;

  /// User's avatar URL (denormalized)
  final String? userPhotoUrl;

  /// Role within the group
  final GroupRole role;

  /// Current membership status
  final MembershipStatus status;

  /// When the user joined/requested to join
  final DateTime joinedAt;

  /// When the membership was last updated
  final DateTime? updatedAt;

  /// Who approved this membership (for request-to-join)
  final String? approvedByUserId;

  /// Optional note (e.g., ban reason)
  final String? note;

  const GroupMembership({
    required this.id,
    required this.groupId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.updatedAt,
    this.approvedByUserId,
    this.note,
  });

  /// Check if this is an admin membership
  bool get isAdmin => role == GroupRole.admin;

  /// Check if membership is active
  bool get isActive => status == MembershipStatus.active;

  /// Check if membership is pending approval
  bool get isPending => status == MembershipStatus.pending;

  /// Check if user was banned
  bool get isBanned => status == MembershipStatus.banned;

  GroupMembership copyWith({
    String? id,
    String? groupId,
    String? userId,
    String? userName,
    String? userPhotoUrl,
    GroupRole? role,
    MembershipStatus? status,
    DateTime? joinedAt,
    DateTime? updatedAt,
    String? approvedByUserId,
    String? note,
  }) {
    return GroupMembership(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhotoUrl: userPhotoUrl ?? this.userPhotoUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      joinedAt: joinedAt ?? this.joinedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      approvedByUserId: approvedByUserId ?? this.approvedByUserId,
      note: note ?? this.note,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        userId,
        userName,
        userPhotoUrl,
        role,
        status,
        joinedAt,
        updatedAt,
        approvedByUserId,
        note,
      ];
}

/// Join request entity for request-to-join groups.
class GroupJoinRequest extends Equatable {
  final String id;
  final String groupId;
  final String userId;
  final String? userName;
  final String? userPhotoUrl;
  final String? message;
  final DateTime requestedAt;

  const GroupJoinRequest({
    required this.id,
    required this.groupId,
    required this.userId,
    this.userName,
    this.userPhotoUrl,
    this.message,
    required this.requestedAt,
  });

  @override
  List<Object?> get props => [
        id,
        groupId,
        userId,
        userName,
        userPhotoUrl,
        message,
        requestedAt,
      ];
}
