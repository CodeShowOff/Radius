import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities/location_group.dart';
import '../domain/entities/group_membership.dart';
import 'models/location_group_model.dart';
import 'models/group_membership_model.dart';

/// Sort options for group listing.
enum GroupSortOption {
  /// Most recently active groups first
  mostActive,

  /// Newest groups first
  newest,

  /// Most members first
  mostMembers,
}

/// Result type for group operations.
sealed class GroupResult<T> {
  const GroupResult();
}

class GroupSuccess<T> extends GroupResult<T> {
  final T data;
  const GroupSuccess(this.data);
}

class GroupFailure<T> extends GroupResult<T> {
  final String message;
  final GroupErrorType type;
  const GroupFailure(this.message, this.type);
}

enum GroupErrorType {
  duplicateName,
  notFound,
  notAuthorized,
  alreadyMember,
  alreadyRequested,
  userBanned,
  invalidData,
  networkError,
  unknown,
}

/// Service for managing location-scoped groups via Firestore.
///
/// Firestore Collections:
/// - `location_groups` - Group metadata
/// - `location_groups/{groupId}/members` - Group memberships
/// - `location_groups/{groupId}/join_requests` - Pending join requests
/// - `location_groups/{groupId}/messages` - Group chat messages
class LocationGroupService {
  final FirebaseFirestore _firestore;
  final Logger _logger;
  final Uuid _uuid;

  // Collection references
  late final CollectionReference<Map<String, dynamic>> _groupsRef;

  LocationGroupService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger(),
        _uuid = const Uuid() {
    _groupsRef = _firestore.collection('location_groups');
  }

  // ==================== GROUP CREATION ====================

  /// Creates a new location group.
  ///
  /// Validates:
  /// - Group name uniqueness within the same country + state
  /// - Creator becomes admin member automatically
  Future<GroupResult<LocationGroup>> createGroup({
    required String name,
    String? description,
    required String countryCode,
    required String stateCode,
    required String countryName,
    required String stateName,
    required String creatorUserId,
    String? creatorUserName,
    String? creatorUserPhotoUrl,
    required GroupVisibility visibility,
  }) async {
    try {
      // Validate name
      final trimmedName = name.trim();
      if (trimmedName.isEmpty || trimmedName.length < 3) {
        return const GroupFailure(
          'Group name must be at least 3 characters',
          GroupErrorType.invalidData,
        );
      }
      if (trimmedName.length > 50) {
        return const GroupFailure(
          'Group name must be 50 characters or less',
          GroupErrorType.invalidData,
        );
      }

      // Check for duplicate name in same location
      final duplicateCheck = await _groupsRef
          .where('countryCode', isEqualTo: countryCode)
          .where('stateCode', isEqualTo: stateCode)
          .where('nameLowercase', isEqualTo: trimmedName.toLowerCase())
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (duplicateCheck.docs.isNotEmpty) {
        return const GroupFailure(
          'A group with this name already exists in this location',
          GroupErrorType.duplicateName,
        );
      }

      // Create group document
      final groupId = _uuid.v4();
      final now = DateTime.now();

      final group = LocationGroupModel(
        id: groupId,
        name: trimmedName,
        description: description?.trim(),
        countryCode: countryCode,
        stateCode: stateCode,
        countryName: countryName,
        stateName: stateName,
        createdByUserId: creatorUserId,
        createdByUserName: creatorUserName,
        visibility: visibility,
        status: GroupStatus.active,
        memberCount: 1,
        createdAt: now,
        lastActivityAt: now,
      );

      // Create admin membership
      final membership = GroupMembershipModel(
        id: creatorUserId,
        groupId: groupId,
        userId: creatorUserId,
        userName: creatorUserName,
        userPhotoUrl: creatorUserPhotoUrl,
        role: GroupRole.admin,
        status: MembershipStatus.active,
        joinedAt: now,
      );

      // Batch write: group + membership
      final batch = _firestore.batch();
      batch.set(_groupsRef.doc(groupId), group.toCreateData());
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(creatorUserId),
        membership.toCreateData(),
      );
      await batch.commit();

      _logger.i('Created group: $groupId in $stateCode, $countryCode');

      // Fetch the created group to get server timestamp
      final createdDoc = await _groupsRef.doc(groupId).get();
      return GroupSuccess(LocationGroupModel.fromFirestore(createdDoc));
    } on FirebaseException catch (e) {
      _logger.e('Firebase error creating group', error: e);
      return const GroupFailure(
        'Failed to create group',
        GroupErrorType.networkError,
      );
    } catch (e) {
      _logger.e('Error creating group', error: e);
      return const GroupFailure(
        'An unexpected error occurred',
        GroupErrorType.unknown,
      );
    }
  }

  // ==================== GROUP DISCOVERY ====================

  /// Gets groups for a specific location (country + state).
  Future<List<LocationGroup>> getGroupsForLocation({
    required String countryCode,
    required String stateCode,
    GroupSortOption sortBy = GroupSortOption.mostActive,
    int limit = 50,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _groupsRef
          .where('countryCode', isEqualTo: countryCode)
          .where('stateCode', isEqualTo: stateCode)
          .where('status', isEqualTo: 'active');

      // Apply sorting
      switch (sortBy) {
        case GroupSortOption.mostActive:
          query = query.orderBy('lastActivityAt', descending: true);
          break;
        case GroupSortOption.newest:
          query = query.orderBy('createdAt', descending: true);
          break;
        case GroupSortOption.mostMembers:
          query = query.orderBy('memberCount', descending: true);
          break;
      }

      final snapshot = await query.limit(limit).get();

      return snapshot.docs
          .map((doc) => LocationGroupModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      _logger.e('Error fetching groups for location', error: e);
      return [];
    }
  }

  /// Streams groups for a location with real-time updates.
  Stream<List<LocationGroup>> streamGroupsForLocation({
    required String countryCode,
    required String stateCode,
    GroupSortOption sortBy = GroupSortOption.mostActive,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _groupsRef
        .where('countryCode', isEqualTo: countryCode)
        .where('stateCode', isEqualTo: stateCode)
        .where('status', isEqualTo: 'active');

    // Apply sorting
    switch (sortBy) {
      case GroupSortOption.mostActive:
        query = query.orderBy('lastActivityAt', descending: true);
        break;
      case GroupSortOption.newest:
        query = query.orderBy('createdAt', descending: true);
        break;
      case GroupSortOption.mostMembers:
        query = query.orderBy('memberCount', descending: true);
        break;
    }

    return query.limit(limit).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => LocationGroupModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Gets a single group by ID.
  Future<LocationGroup?> getGroupById(String groupId) async {
    try {
      final doc = await _groupsRef.doc(groupId).get();
      if (!doc.exists) return null;
      return LocationGroupModel.fromFirestore(doc);
    } catch (e) {
      _logger.e('Error fetching group $groupId', error: e);
      return null;
    }
  }

  /// Streams a single group with real-time updates.
  Stream<LocationGroup?> streamGroup(String groupId) {
    return _groupsRef.doc(groupId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return LocationGroupModel.fromFirestore(doc);
    });
  }

  /// Gets groups the user is a member of.
  Future<List<LocationGroup>> getUserGroups(String userId) async {
    try {
      // Query all groups where user is an active member
      // This requires a collection group query
      final membershipQuery = await _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      if (membershipQuery.docs.isEmpty) return [];

      // Get group IDs
      final groupIds = membershipQuery.docs.map((doc) {
        // Path: location_groups/{groupId}/members/{memberId}
        return doc.reference.parent.parent!.id;
      }).toSet();

      // Fetch groups
      final groups = <LocationGroup>[];
      for (final groupId in groupIds) {
        final group = await getGroupById(groupId);
        if (group != null && group.isActive) {
          groups.add(group);
        }
      }

      // Sort by last activity
      groups.sort((a, b) {
        final aTime = a.lastActivityAt ?? a.createdAt;
        final bTime = b.lastActivityAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      return groups;
    } catch (e) {
      _logger.e('Error fetching user groups', error: e);
      return [];
    }
  }

  /// Streams groups the user is a member of.
  Stream<List<LocationGroup>> streamUserGroups(String userId) {
    return _firestore
        .collectionGroup('members')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return <LocationGroup>[];

      final groupIds = snapshot.docs.map((doc) {
        return doc.reference.parent.parent!.id;
      }).toSet();

      final groups = <LocationGroup>[];
      for (final groupId in groupIds) {
        final group = await getGroupById(groupId);
        if (group != null && group.isActive) {
          groups.add(group);
        }
      }

      groups.sort((a, b) {
        final aTime = a.lastActivityAt ?? a.createdAt;
        final bTime = b.lastActivityAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });

      return groups;
    });
  }

  // ==================== MEMBERSHIP MANAGEMENT ====================

  /// Joins a public group.
  Future<GroupResult<GroupMembership>> joinPublicGroup({
    required String groupId,
    required String userId,
    String? userName,
    String? userPhotoUrl,
  }) async {
    try {
      // Verify group exists and is public
      final group = await getGroupById(groupId);
      if (group == null) {
        return const GroupFailure('Group not found', GroupErrorType.notFound);
      }
      if (!group.isActive) {
        return const GroupFailure(
          'This group is no longer active',
          GroupErrorType.notFound,
        );
      }
      if (!group.isPublic) {
        return const GroupFailure(
          'This group requires approval to join',
          GroupErrorType.notAuthorized,
        );
      }

      // Check if already a member
      final existingMembership = await _getMembership(groupId, userId);
      if (existingMembership != null) {
        if (existingMembership.isBanned) {
          return const GroupFailure(
            'You have been banned from this group',
            GroupErrorType.userBanned,
          );
        }
        if (existingMembership.isActive) {
          return const GroupFailure(
            'You are already a member of this group',
            GroupErrorType.alreadyMember,
          );
        }
      }

      // Create membership
      final membership = GroupMembershipModel(
        id: userId,
        groupId: groupId,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        role: GroupRole.member,
        status: MembershipStatus.active,
        joinedAt: DateTime.now(),
      );

      // Update membership and increment member count
      final batch = _firestore.batch();
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(userId),
        membership.toCreateData(),
      );
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(1),
      });
      await batch.commit();

      _logger.i('User $userId joined group $groupId');
      return GroupSuccess(membership);
    } on FirebaseException catch (e) {
      _logger.e('Firebase error joining group', error: e);
      return const GroupFailure(
        'Failed to join group',
        GroupErrorType.networkError,
      );
    } catch (e) {
      _logger.e('Error joining group', error: e);
      return const GroupFailure(
        'An unexpected error occurred',
        GroupErrorType.unknown,
      );
    }
  }

  /// Requests to join a request-to-join group.
  Future<GroupResult<GroupJoinRequest>> requestToJoin({
    required String groupId,
    required String userId,
    String? userName,
    String? userPhotoUrl,
    String? message,
  }) async {
    try {
      // Verify group exists and requires approval
      final group = await getGroupById(groupId);
      if (group == null) {
        return const GroupFailure('Group not found', GroupErrorType.notFound);
      }
      if (!group.isActive) {
        return const GroupFailure(
          'This group is no longer active',
          GroupErrorType.notFound,
        );
      }

      // Check if already a member
      final existingMembership = await _getMembership(groupId, userId);
      if (existingMembership != null) {
        if (existingMembership.isBanned) {
          return const GroupFailure(
            'You have been banned from this group',
            GroupErrorType.userBanned,
          );
        }
        if (existingMembership.isActive) {
          return const GroupFailure(
            'You are already a member of this group',
            GroupErrorType.alreadyMember,
          );
        }
        if (existingMembership.isPending) {
          return const GroupFailure(
            'You already have a pending request',
            GroupErrorType.alreadyRequested,
          );
        }
      }

      // Check for existing request
      final existingRequest = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .doc(userId)
          .get();

      if (existingRequest.exists) {
        return const GroupFailure(
          'You already have a pending request',
          GroupErrorType.alreadyRequested,
        );
      }

      // Create join request
      final request = GroupJoinRequestModel(
        id: userId,
        groupId: groupId,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        message: message,
        requestedAt: DateTime.now(),
      );

      await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .doc(userId)
          .set(request.toCreateData());

      _logger.i('User $userId requested to join group $groupId');
      return GroupSuccess(request);
    } on FirebaseException catch (e) {
      _logger.e('Firebase error requesting to join', error: e);
      return const GroupFailure(
        'Failed to send request',
        GroupErrorType.networkError,
      );
    } catch (e) {
      _logger.e('Error requesting to join', error: e);
      return const GroupFailure(
        'An unexpected error occurred',
        GroupErrorType.unknown,
      );
    }
  }

  /// Approves a join request (admin only).
  Future<GroupResult<GroupMembership>> approveJoinRequest({
    required String groupId,
    required String requestUserId,
    required String adminUserId,
  }) async {
    try {
      // Verify admin status
      final adminMembership = await _getMembership(groupId, adminUserId);
      if (adminMembership == null || !adminMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can approve requests',
          GroupErrorType.notAuthorized,
        );
      }

      // Get join request
      final requestDoc = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .doc(requestUserId)
          .get();

      if (!requestDoc.exists) {
        return const GroupFailure(
          'Join request not found',
          GroupErrorType.notFound,
        );
      }

      final requestData = requestDoc.data()!;

      // Create membership
      final membership = GroupMembershipModel(
        id: requestUserId,
        groupId: groupId,
        userId: requestUserId,
        userName: requestData['userName'] as String?,
        userPhotoUrl: requestData['userPhotoUrl'] as String?,
        role: GroupRole.member,
        status: MembershipStatus.active,
        joinedAt: DateTime.now(),
        approvedByUserId: adminUserId,
      );

      // Batch: create membership, delete request, increment count
      final batch = _firestore.batch();
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(requestUserId),
        membership.toCreateData(),
      );
      batch.delete(requestDoc.reference);
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(1),
      });
      await batch.commit();

      _logger.i('Admin $adminUserId approved $requestUserId for group $groupId');
      return GroupSuccess(membership);
    } catch (e) {
      _logger.e('Error approving join request', error: e);
      return const GroupFailure(
        'Failed to approve request',
        GroupErrorType.unknown,
      );
    }
  }

  /// Rejects a join request (admin only).
  Future<GroupResult<void>> rejectJoinRequest({
    required String groupId,
    required String requestUserId,
    required String adminUserId,
  }) async {
    try {
      // Verify admin status
      final adminMembership = await _getMembership(groupId, adminUserId);
      if (adminMembership == null || !adminMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can reject requests',
          GroupErrorType.notAuthorized,
        );
      }

      await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .doc(requestUserId)
          .delete();

      _logger.i('Admin $adminUserId rejected $requestUserId for group $groupId');
      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error rejecting join request', error: e);
      return const GroupFailure(
        'Failed to reject request',
        GroupErrorType.unknown,
      );
    }
  }

  /// Gets pending join requests for a group (admin only).
  Future<List<GroupJoinRequest>> getJoinRequests(String groupId) async {
    try {
      final snapshot = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => GroupJoinRequestModel.fromFirestore(doc, groupId))
          .toList();
    } catch (e) {
      _logger.e('Error fetching join requests', error: e);
      return [];
    }
  }

  /// Streams pending join requests for a group.
  Stream<List<GroupJoinRequest>> streamJoinRequests(String groupId) {
    return _groupsRef
        .doc(groupId)
        .collection('join_requests')
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => GroupJoinRequestModel.fromFirestore(doc, groupId))
          .toList();
    });
  }

  /// Leaves a group.
  Future<GroupResult<void>> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final membership = await _getMembership(groupId, userId);
      if (membership == null || !membership.isActive) {
        return const GroupFailure(
          'You are not a member of this group',
          GroupErrorType.notFound,
        );
      }

      // Check if user is the only admin
      if (membership.isAdmin) {
        final admins = await _groupsRef
            .doc(groupId)
            .collection('members')
            .where('role', isEqualTo: 'admin')
            .where('status', isEqualTo: 'active')
            .get();

        if (admins.docs.length == 1) {
          return const GroupFailure(
            'You are the only admin. Please assign another admin before leaving.',
            GroupErrorType.notAuthorized,
          );
        }
      }

      // Update membership status and decrement count
      final batch = _firestore.batch();
      batch.update(
        _groupsRef.doc(groupId).collection('members').doc(userId),
        {
          'status': 'left',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(-1),
      });
      await batch.commit();

      _logger.i('User $userId left group $groupId');
      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error leaving group', error: e);
      return const GroupFailure(
        'Failed to leave group',
        GroupErrorType.unknown,
      );
    }
  }

  /// Gets membership status for a user in a group.
  Future<GroupMembership?> getMembershipStatus(
    String groupId,
    String userId,
  ) async {
    return _getMembership(groupId, userId);
  }

  /// Gets all active members of a group.
  Future<List<GroupMembership>> getGroupMembers(String groupId) async {
    try {
      final snapshot = await _groupsRef
          .doc(groupId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .orderBy('joinedAt')
          .get();

      return snapshot.docs
          .map((doc) => GroupMembershipModel.fromFirestore(doc, groupId))
          .toList();
    } catch (e) {
      _logger.e('Error fetching group members', error: e);
      return [];
    }
  }

  /// Streams group members.
  Stream<List<GroupMembership>> streamGroupMembers(String groupId) {
    return _groupsRef
        .doc(groupId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .orderBy('joinedAt')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => GroupMembershipModel.fromFirestore(doc, groupId))
          .toList();
    });
  }

  // ==================== ADMIN ACTIONS ====================

  /// Promotes a member to admin.
  Future<GroupResult<void>> promoteToAdmin({
    required String groupId,
    required String targetUserId,
    required String adminUserId,
  }) async {
    try {
      // Verify caller is admin
      final callerMembership = await _getMembership(groupId, adminUserId);
      if (callerMembership == null || !callerMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can promote members',
          GroupErrorType.notAuthorized,
        );
      }

      // Verify target is active member
      final targetMembership = await _getMembership(groupId, targetUserId);
      if (targetMembership == null || !targetMembership.isActive) {
        return const GroupFailure(
          'User is not an active member',
          GroupErrorType.notFound,
        );
      }

      await _groupsRef.doc(groupId).collection('members').doc(targetUserId).update({
        'role': 'admin',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _logger.i('User $targetUserId promoted to admin in group $groupId');
      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error promoting member', error: e);
      return const GroupFailure(
        'Failed to promote member',
        GroupErrorType.unknown,
      );
    }
  }

  /// Removes a member from the group (admin only).
  Future<GroupResult<void>> removeMember({
    required String groupId,
    required String targetUserId,
    required String adminUserId,
    bool ban = false,
    String? reason,
  }) async {
    try {
      // Verify caller is admin
      final callerMembership = await _getMembership(groupId, adminUserId);
      if (callerMembership == null || !callerMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can remove members',
          GroupErrorType.notAuthorized,
        );
      }

      // Cannot remove yourself this way
      if (targetUserId == adminUserId) {
        return const GroupFailure(
          'Use leave group instead',
          GroupErrorType.invalidData,
        );
      }

      final batch = _firestore.batch();
      batch.update(
        _groupsRef.doc(groupId).collection('members').doc(targetUserId),
        {
          'status': ban ? 'banned' : 'left',
          'note': reason,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(-1),
      });
      await batch.commit();

      _logger.i('User $targetUserId ${ban ? "banned from" : "removed from"} group $groupId');
      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error removing member', error: e);
      return const GroupFailure(
        'Failed to remove member',
        GroupErrorType.unknown,
      );
    }
  }

  /// Updates group settings (admin only).
  Future<GroupResult<LocationGroup>> updateGroup({
    required String groupId,
    required String adminUserId,
    String? name,
    String? description,
    GroupVisibility? visibility,
  }) async {
    try {
      // Verify caller is admin
      final callerMembership = await _getMembership(groupId, adminUserId);
      if (callerMembership == null || !callerMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can update group settings',
          GroupErrorType.notAuthorized,
        );
      }

      final updates = <String, dynamic>{};

      if (name != null) {
        final trimmedName = name.trim();
        if (trimmedName.length < 3 || trimmedName.length > 50) {
          return const GroupFailure(
            'Group name must be 3-50 characters',
            GroupErrorType.invalidData,
          );
        }
        
        // Check for duplicate
        final group = await getGroupById(groupId);
        if (group != null) {
          final duplicateCheck = await _groupsRef
              .where('countryCode', isEqualTo: group.countryCode)
              .where('stateCode', isEqualTo: group.stateCode)
              .where('nameLowercase', isEqualTo: trimmedName.toLowerCase())
              .where('status', isEqualTo: 'active')
              .get();

          if (duplicateCheck.docs.any((doc) => doc.id != groupId)) {
            return const GroupFailure(
              'A group with this name already exists in this location',
              GroupErrorType.duplicateName,
            );
          }
        }

        updates['name'] = trimmedName;
        updates['nameLowercase'] = trimmedName.toLowerCase();
      }

      if (description != null) {
        updates['description'] = description.trim();
      }

      if (visibility != null) {
        updates['visibility'] = visibility.name;
      }

      if (updates.isEmpty) {
        final group = await getGroupById(groupId);
        return group != null
            ? GroupSuccess(group)
            : const GroupFailure('Group not found', GroupErrorType.notFound);
      }

      await _groupsRef.doc(groupId).update(updates);

      final updatedGroup = await getGroupById(groupId);
      return updatedGroup != null
          ? GroupSuccess(updatedGroup)
          : const GroupFailure('Group not found', GroupErrorType.notFound);
    } catch (e) {
      _logger.e('Error updating group', error: e);
      return const GroupFailure(
        'Failed to update group',
        GroupErrorType.unknown,
      );
    }
  }

  /// Archives a group (admin only).
  Future<GroupResult<void>> archiveGroup({
    required String groupId,
    required String adminUserId,
  }) async {
    try {
      final callerMembership = await _getMembership(groupId, adminUserId);
      if (callerMembership == null || !callerMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can archive groups',
          GroupErrorType.notAuthorized,
        );
      }

      await _groupsRef.doc(groupId).update({
        'status': 'archived',
      });

      _logger.i('Group $groupId archived');
      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error archiving group', error: e);
      return const GroupFailure(
        'Failed to archive group',
        GroupErrorType.unknown,
      );
    }
  }

  // ==================== HELPER METHODS ====================

  Future<GroupMembership?> _getMembership(String groupId, String userId) async {
    try {
      final doc = await _groupsRef
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .get();

      if (!doc.exists) return null;
      return GroupMembershipModel.fromFirestore(doc, groupId);
    } catch (e) {
      _logger.e('Error getting membership', error: e);
      return null;
    }
  }

  /// Updates last activity timestamp for a group (called when messages are sent).
  Future<void> updateLastActivity(String groupId, String? messagePreview) async {
    try {
      await _groupsRef.doc(groupId).update({
        'lastActivityAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': messagePreview,
      });
    } catch (e) {
      _logger.w('Error updating last activity', error: e);
    }
  }
}
