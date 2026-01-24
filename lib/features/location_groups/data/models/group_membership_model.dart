import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/group_membership.dart';

/// Firestore model for GroupMembership entity.
///
/// Firestore Schema:
/// ```
/// location_groups/{groupId}/members/{membershipId}
///   - userId: string
///   - userName: string?
///   - userPhotoUrl: string?
///   - role: string ('admin' | 'member')
///   - status: string ('active' | 'pending' | 'banned' | 'left')
///   - joinedAt: timestamp
///   - updatedAt: timestamp?
///   - approvedByUserId: string?
///   - note: string?
///   - unreadCount: number
///   - lastReadAt: timestamp?
/// ```
class GroupMembershipModel extends GroupMembership {
  const GroupMembershipModel({
    required super.id,
    required super.groupId,
    required super.userId,
    super.userName,
    super.userPhotoUrl,
    required super.role,
    required super.status,
    required super.joinedAt,
    super.updatedAt,
    super.approvedByUserId,
    super.note,
    super.unreadCount = 0,
    super.lastReadAt,
  });

  /// Creates model from Firestore document.
  factory GroupMembershipModel.fromFirestore(
    DocumentSnapshot doc,
    String groupId,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    return GroupMembershipModel(
      id: doc.id,
      groupId: groupId,
      userId: data['userId'] as String,
      userName: data['userName'] as String?,
      userPhotoUrl: data['userPhotoUrl'] as String?,
      role: _parseRole(data['role'] as String?),
      status: _parseStatus(data['status'] as String?),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      approvedByUserId: data['approvedByUserId'] as String?,
      note: data['note'] as String?,
      unreadCount: data['unreadCount'] as int? ?? 0,
      lastReadAt: (data['lastReadAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Creates model from GroupMembership entity.
  factory GroupMembershipModel.fromEntity(GroupMembership membership) {
    return GroupMembershipModel(
      id: membership.id,
      groupId: membership.groupId,
      userId: membership.userId,
      userName: membership.userName,
      userPhotoUrl: membership.userPhotoUrl,
      role: membership.role,
      status: membership.status,
      joinedAt: membership.joinedAt,
      updatedAt: membership.updatedAt,
      approvedByUserId: membership.approvedByUserId,
      note: membership.note,
      unreadCount: membership.unreadCount,
      lastReadAt: membership.lastReadAt,
    );
  }

  /// Converts model to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'role': role.name,
      'status': status.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'approvedByUserId': approvedByUserId,
      'note': note,
      'unreadCount': unreadCount,
      'lastReadAt': lastReadAt != null ? Timestamp.fromDate(lastReadAt!) : null,
    };
  }

  /// Converts to data for creating a new membership (uses server timestamp).
  Map<String, dynamic> toCreateData() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'role': role.name,
      'status': status.name,
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': null,
      'approvedByUserId': approvedByUserId,
      'note': note,
      'unreadCount': 0,
      'lastReadAt': FieldValue.serverTimestamp(),
    };
  }

  static GroupRole _parseRole(String? value) {
    switch (value) {
      case 'admin':
        return GroupRole.admin;
      case 'member':
      default:
        return GroupRole.member;
    }
  }

  static MembershipStatus _parseStatus(String? value) {
    switch (value) {
      case 'pending':
        return MembershipStatus.pending;
      case 'banned':
        return MembershipStatus.banned;
      case 'left':
        return MembershipStatus.left;
      case 'active':
      default:
        return MembershipStatus.active;
    }
  }
}

/// Firestore model for GroupJoinRequest.
class GroupJoinRequestModel extends GroupJoinRequest {
  const GroupJoinRequestModel({
    required super.id,
    required super.groupId,
    required super.userId,
    super.userName,
    super.userPhotoUrl,
    super.message,
    required super.requestedAt,
  });

  factory GroupJoinRequestModel.fromFirestore(
    DocumentSnapshot doc,
    String groupId,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    return GroupJoinRequestModel(
      id: doc.id,
      groupId: groupId,
      userId: data['userId'] as String,
      userName: data['userName'] as String?,
      userPhotoUrl: data['userPhotoUrl'] as String?,
      message: data['message'] as String?,
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toCreateData() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'message': message,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
    };
  }
}
