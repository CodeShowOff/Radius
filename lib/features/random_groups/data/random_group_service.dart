import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/exceptions.dart';
import '../domain/entities/join_request.dart';
import '../domain/entities/random_group.dart';
import '../domain/entities/random_group_member.dart';
import 'models/join_request_model.dart';
import 'models/random_group_member_model.dart';
import 'models/random_group_model.dart';

/// Result type for random group operations.
sealed class RandomGroupResult<T> {
  const RandomGroupResult();
}

class RandomGroupSuccess<T> extends RandomGroupResult<T> {
  final T data;
  const RandomGroupSuccess(this.data);
}

class RandomGroupFailure<T> extends RandomGroupResult<T> {
  final String message;
  final RandomGroupErrorType type;
  const RandomGroupFailure(this.message, this.type);
}

enum RandomGroupErrorType {
  alreadyRequested,
  alreadyMember,
  notFound,
  notAuthorized,
  invalidData,
  networkError,
  cooldownActive,
  unknown,
}

/// Service for managing internet-based random groups.
///
/// Firestore Collections:
/// - `random_groups` - Group metadata
/// - `random_groups/{groupId}/members` - Approved members
/// - `random_groups/{groupId}/join_requests` - Pending/handled join requests
/// - `random_groups/{groupId}/messages` - Group chat messages
///
/// Key behaviors:
/// - Groups are not location-based (internet-only)
/// - Discoverable by all users
/// - Membership requires admin approval
/// - Only approved members can participate in chat
class RandomGroupService {
  final FirebaseFirestore _firestore;
  final Logger _logger;
  final Uuid _uuid;

  late final CollectionReference<Map<String, dynamic>> _groupsRef;

  /// Cooldown period for rejected users to reapply (24 hours)
  static const Duration rejectionCooldown = Duration(hours: 24);

  RandomGroupService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger(),
        _uuid = const Uuid() {
    _groupsRef = _firestore.collection('random_groups');
  }

  DatabaseException _mapFirestoreException(FirebaseException e) {
    String message;
    switch (e.code) {
      case 'permission-denied':
        message = 'Permission denied. Please check your authentication.';
        break;
      case 'not-found':
        message = 'Group not found';
        break;
      case 'unavailable':
        message = 'Service temporarily unavailable';
        break;
      default:
        message = e.message ?? 'Database error occurred';
    }

    return DatabaseException(
      message: message,
      code: e.code,
      originalError: e,
    );
  }

  // ==================== GROUP CREATION ====================

  /// Creates a new random group.
  Future<RandomGroupResult<RandomGroup>> createGroup({
    required String name,
    String? topic,
    String? description,
    required String creatorId,
    required String creatorUsername,
    String? creatorDisplayName,
    String? creatorPhotoUrl,
  }) async {
    try {
      // Validate name
      final trimmedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (trimmedName.isEmpty || trimmedName.length < 2) {
        return const RandomGroupFailure(
          'Group name must be at least 2 characters',
          RandomGroupErrorType.invalidData,
        );
      }
      if (trimmedName.length > 50) {
        return const RandomGroupFailure(
          'Group name must be 50 characters or less',
          RandomGroupErrorType.invalidData,
        );
      }

      // Create group document
      final groupId = _uuid.v4();
      final group = RandomGroupModel.create(
        id: groupId,
        name: trimmedName,
        topic: topic?.trim(),
        description: description?.trim(),
        creatorId: creatorId,
        creatorUsername: creatorUsername,
        creatorDisplayName: creatorDisplayName,
        creatorPhotoUrl: creatorPhotoUrl,
      );

      final batch = _firestore.batch();

      // Create group document
      batch.set(
        _groupsRef.doc(groupId),
        group.toFirestore(useServerTimestamp: true),
      );

      // Add creator as first member (and admin)
      final creatorMember = RandomGroupMemberModel.create(
        userId: creatorId,
        username: creatorUsername,
        displayName: creatorDisplayName,
        photoUrl: creatorPhotoUrl,
        isAdmin: true,
      );
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(creatorId),
        creatorMember.toFirestore(useServerTimestamp: true),
      );

      await batch.commit();

      _logger.i('Created random group: $groupId with name: $trimmedName');
      return RandomGroupSuccess(group.toEntity());
    } on FirebaseException catch (e, stack) {
      _logger.e('Error creating random group', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error creating random group', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to create group: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  // ==================== GROUP QUERIES ====================

  /// Stream of all active random groups (for discovery).
  Stream<List<RandomGroup>> watchActiveGroups() {
    return _groupsRef
        .where('status', isEqualTo: 'active')
        .orderBy('lastActiveAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RandomGroupModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Stream of groups filtered by topic.
  Stream<List<RandomGroup>> watchGroupsByTopic(String topic) {
    return _groupsRef
        .where('status', isEqualTo: 'active')
        .where('topic', isEqualTo: topic)
        .orderBy('lastActiveAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RandomGroupModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Stream of groups the user is a member of.
  ///
  /// Uses a collection group query on the 'members' subcollection to efficiently
  /// find all groups where the user is a member, then fetches the group details.
  Stream<List<RandomGroup>> watchUserMemberships(String userId) {
    // Use collection group query to find all memberships for this user
    return _firestore
        .collectionGroup('members')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return <RandomGroup>[];

      // Extract group IDs from the member documents
      final groupIds = snapshot.docs
          .map((doc) {
            // Path format: random_groups/{groupId}/members/{memberId}
            final pathSegments = doc.reference.path.split('/');
            // Validate path structure: must have at least 4 segments
            // and be from random_groups collection
            if (pathSegments.length >= 4 && pathSegments[0] == 'random_groups') {
              return pathSegments[1]; // groupId is at index 1
            }
            return null;
          })
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();

      if (groupIds.isEmpty) return <RandomGroup>[];

      // Fetch group details for each group (in batches of 10 for whereIn limitation)
      final memberGroups = <RandomGroup>[];
      for (var i = 0; i < groupIds.length; i += 10) {
        final batchIds = groupIds.sublist(
          i,
          (i + 10 > groupIds.length) ? groupIds.length : i + 10,
        );
        final groupDocs = await _groupsRef
            .where(FieldPath.documentId, whereIn: batchIds)
            .where('status', isEqualTo: 'active')
            .get();

        for (final doc in groupDocs.docs) {
          memberGroups.add(RandomGroupModel.fromFirestore(doc).toEntity());
        }
      }

      return memberGroups;
    });
  }

  /// Stream of groups created by the user.
  Stream<List<RandomGroup>> watchUserCreatedGroups(String userId) {
    return _groupsRef
        .where('creatorId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RandomGroupModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Gets a single group by ID.
  Future<RandomGroup?> getGroup(String groupId) async {
    try {
      final doc = await _groupsRef.doc(groupId).get();
      if (!doc.exists) return null;
      return RandomGroupModel.fromFirestore(doc).toEntity();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error getting group', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    }
  }

  /// Stream of a single group for real-time updates.
  Stream<RandomGroup?> watchGroup(String groupId) {
    return _groupsRef.doc(groupId).snapshots().map((doc) =>
        doc.exists ? RandomGroupModel.fromFirestore(doc).toEntity() : null);
  }

  // ==================== MEMBERSHIP MANAGEMENT ====================

  /// Checks if a user is a member of a group.
  Future<bool> isMember(String groupId, String userId) async {
    try {
      final doc =
          await _groupsRef.doc(groupId).collection('members').doc(userId).get();
      return doc.exists;
    } catch (e) {
      _logger.w('Failed to check membership', error: e);
      return false;
    }
  }

  /// Stream of members for a group.
  /// Limited to 200 members for performance.
  Stream<List<RandomGroupMember>> watchMembers(String groupId) {
    return _groupsRef
        .doc(groupId)
        .collection('members')
        .orderBy('joinedAt', descending: false)
        .limit(200)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RandomGroupMemberModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Removes a member from a group (admin only).
  Future<RandomGroupResult<void>> removeMember({
    required String groupId,
    required String memberId,
    required String adminId,
  }) async {
    try {
      // Check if admin has permission
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);
      if (!group.adminIds.contains(adminId)) {
        return const RandomGroupFailure(
          'Only admins can remove members',
          RandomGroupErrorType.notAuthorized,
        );
      }

      // Cannot remove creator
      if (memberId == group.creatorId) {
        return const RandomGroupFailure(
          'Cannot remove the group creator',
          RandomGroupErrorType.notAuthorized,
        );
      }

      final batch = _firestore.batch();

      // Remove member
      batch.delete(_groupsRef.doc(groupId).collection('members').doc(memberId));

      // Update member count
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(-1),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      // Remove from admin list if they were an admin
      if (group.adminIds.contains(memberId)) {
        batch.update(_groupsRef.doc(groupId), {
          'adminIds': FieldValue.arrayRemove([memberId]),
        });
      }

      await batch.commit();

      _logger.i('Removed member $memberId from group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error removing member', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error removing member', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to remove member: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  /// Promotes a member to admin.
  Future<RandomGroupResult<void>> promoteToAdmin({
    required String groupId,
    required String memberId,
    required String adminId,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);
      if (!group.adminIds.contains(adminId)) {
        return const RandomGroupFailure(
          'Only admins can promote members',
          RandomGroupErrorType.notAuthorized,
        );
      }

      final batch = _firestore.batch();

      // Add to admin list
      batch.update(_groupsRef.doc(groupId), {
        'adminIds': FieldValue.arrayUnion([memberId]),
      });

      // Update member's admin status
      batch.update(
        _groupsRef.doc(groupId).collection('members').doc(memberId),
        {'isAdmin': true},
      );

      await batch.commit();

      _logger.i('Promoted member $memberId to admin in group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error promoting member', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error promoting member', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to promote member: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  /// User leaves a group voluntarily.
  Future<RandomGroupResult<void>> leaveGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);

      // Creator cannot leave - they must delete the group
      if (userId == group.creatorId) {
        return const RandomGroupFailure(
          'Group creator cannot leave. Delete the group instead.',
          RandomGroupErrorType.notAuthorized,
        );
      }

      final batch = _firestore.batch();

      // Remove member
      batch.delete(_groupsRef.doc(groupId).collection('members').doc(userId));

      // Update member count
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(-1),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      // Remove from admin list if they were an admin
      if (group.adminIds.contains(userId)) {
        batch.update(_groupsRef.doc(groupId), {
          'adminIds': FieldValue.arrayRemove([userId]),
        });
      }

      await batch.commit();

      _logger.i('User $userId left group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error leaving group', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error leaving group', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to leave group: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  // ==================== JOIN REQUEST MANAGEMENT ====================

  /// Submits a join request to a group.
  Future<RandomGroupResult<JoinRequest>> requestToJoin({
    required String groupId,
    required String requesterId,
    required String requesterUsername,
    String? requesterDisplayName,
    String? requesterPhotoUrl,
    String? message,
  }) async {
    try {
      // Check if group exists
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      // Check if already a member
      final memberDoc = await _groupsRef
          .doc(groupId)
          .collection('members')
          .doc(requesterId)
          .get();
      if (memberDoc.exists) {
        return const RandomGroupFailure(
          'You are already a member of this group',
          RandomGroupErrorType.alreadyMember,
        );
      }

      // Check for existing pending request
      final existingPending = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .where('requesterId', isEqualTo: requesterId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existingPending.docs.isNotEmpty) {
        return const RandomGroupFailure(
          'You already have a pending request for this group',
          RandomGroupErrorType.alreadyRequested,
        );
      }

      // Check for recent rejection (cooldown)
      final recentRejection = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .where('requesterId', isEqualTo: requesterId)
          .where('status', isEqualTo: 'rejected')
          .orderBy('handledAt', descending: true)
          .limit(1)
          .get();

      if (recentRejection.docs.isNotEmpty) {
        final lastRejection =
            JoinRequestModel.fromFirestore(recentRejection.docs.first);
        if (lastRejection.handledAt != null) {
          final cooldownEnd =
              lastRejection.handledAt!.add(rejectionCooldown);
          if (DateTime.now().isBefore(cooldownEnd)) {
            final remaining = cooldownEnd.difference(DateTime.now());
            return RandomGroupFailure(
              'You can request again in ${remaining.inHours} hours',
              RandomGroupErrorType.cooldownActive,
            );
          }
        }
      }

      // Create the join request
      final requestId = _uuid.v4();
      final request = JoinRequestModel.create(
        id: requestId,
        groupId: groupId,
        requesterId: requesterId,
        requesterUsername: requesterUsername,
        requesterDisplayName: requesterDisplayName,
        requesterPhotoUrl: requesterPhotoUrl,
        message: message?.trim(),
      );

      final batch = _firestore.batch();

      batch.set(
        _groupsRef.doc(groupId).collection('join_requests').doc(requestId),
        request.toFirestore(useServerTimestamp: true),
      );

      // Increment pending request count
      batch.update(_groupsRef.doc(groupId), {
        'pendingRequestCount': FieldValue.increment(1),
      });

      await batch.commit();

      _logger.i('Join request created: $requestId for group $groupId');
      return RandomGroupSuccess(request.toEntity());
    } on FirebaseException catch (e, stack) {
      _logger.e('Error creating join request', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    }
  }

  /// Stream of pending join requests for a group (admin only).
  Stream<List<JoinRequest>> watchPendingRequests(String groupId) {
    return _groupsRef
        .doc(groupId)
        .collection('join_requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('requestedAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => JoinRequestModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Gets the user's request status for a group.
  Future<JoinRequest?> getUserRequestStatus(
      String groupId, String userId) async {
    try {
      final requests = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .where('requesterId', isEqualTo: userId)
          .orderBy('requestedAt', descending: true)
          .limit(1)
          .get();

      if (requests.docs.isEmpty) return null;
      return JoinRequestModel.fromFirestore(requests.docs.first).toEntity();
    } catch (e) {
      _logger.w('Failed to get request status', error: e);
      return null;
    }
  }

  /// Approves a join request (admin only).
  Future<RandomGroupResult<void>> approveRequest({
    required String groupId,
    required String requestId,
    required String adminId,
  }) async {
    try {
      // Verify admin permission
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);
      if (!group.adminIds.contains(adminId)) {
        return const RandomGroupFailure(
          'Only admins can approve requests',
          RandomGroupErrorType.notAuthorized,
        );
      }

      // Get the request
      final requestDoc = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        return const RandomGroupFailure(
          'Request not found',
          RandomGroupErrorType.notFound,
        );
      }

      final request = JoinRequestModel.fromFirestore(requestDoc);
      if (request.status != JoinRequestStatus.pending) {
        return const RandomGroupFailure(
          'Request has already been handled',
          RandomGroupErrorType.invalidData,
        );
      }

      final batch = _firestore.batch();

      // Update request status
      batch.update(requestDoc.reference, {
        'status': 'approved',
        'handledAt': FieldValue.serverTimestamp(),
        'handledBy': adminId,
      });

      // Add as member
      final member = RandomGroupMemberModel.create(
        userId: request.requesterId,
        username: request.requesterUsername,
        displayName: request.requesterDisplayName,
        photoUrl: request.requesterPhotoUrl,
      );
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(request.requesterId),
        member.toFirestore(useServerTimestamp: true),
      );

      // Update group counts
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(1),
        'pendingRequestCount': FieldValue.increment(-1),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      _logger.i('Approved request $requestId for group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error approving request', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error approving request', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to approve request: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  /// Rejects a join request (admin only).
  Future<RandomGroupResult<void>> rejectRequest({
    required String groupId,
    required String requestId,
    required String adminId,
  }) async {
    try {
      // Verify admin permission
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);
      if (!group.adminIds.contains(adminId)) {
        return const RandomGroupFailure(
          'Only admins can reject requests',
          RandomGroupErrorType.notAuthorized,
        );
      }

      // Get the request
      final requestDoc = await _groupsRef
          .doc(groupId)
          .collection('join_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        return const RandomGroupFailure(
          'Request not found',
          RandomGroupErrorType.notFound,
        );
      }

      final request = JoinRequestModel.fromFirestore(requestDoc);
      if (request.status != JoinRequestStatus.pending) {
        return const RandomGroupFailure(
          'Request has already been handled',
          RandomGroupErrorType.invalidData,
        );
      }

      final batch = _firestore.batch();

      // Update request status
      batch.update(requestDoc.reference, {
        'status': 'rejected',
        'handledAt': FieldValue.serverTimestamp(),
        'handledBy': adminId,
      });

      // Update pending count
      batch.update(_groupsRef.doc(groupId), {
        'pendingRequestCount': FieldValue.increment(-1),
      });

      await batch.commit();

      _logger.i('Rejected request $requestId for group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error rejecting request', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error rejecting request', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to reject request: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  // ==================== GROUP MANAGEMENT ====================

  /// Updates group details (admin only).
  Future<RandomGroupResult<void>> updateGroup({
    required String groupId,
    required String adminId,
    String? name,
    String? topic,
    String? description,
    String? photoUrl,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);
      if (!group.adminIds.contains(adminId)) {
        return const RandomGroupFailure(
          'Only admins can update group details',
          RandomGroupErrorType.notAuthorized,
        );
      }

      final updates = <String, dynamic>{
        'lastActiveAt': FieldValue.serverTimestamp(),
      };

      if (name != null) {
        final trimmedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (trimmedName.length < 2 || trimmedName.length > 50) {
          return const RandomGroupFailure(
            'Group name must be 2-50 characters',
            RandomGroupErrorType.invalidData,
          );
        }
        updates['name'] = trimmedName;
      }

      if (topic != null) {
        updates['topic'] = topic.trim();
      }

      if (description != null) {
        updates['description'] = description.trim();
      }

      if (photoUrl != null) {
        updates['photoUrl'] = photoUrl;
      }

      await _groupsRef.doc(groupId).update(updates);

      _logger.i('Updated group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error updating group', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error updating group', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to update group: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }

  /// Deletes a group (creator only).
  Future<RandomGroupResult<void>> deleteGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        return const RandomGroupFailure(
          'Group not found',
          RandomGroupErrorType.notFound,
        );
      }

      final group = RandomGroupModel.fromFirestore(groupDoc);
      if (group.creatorId != userId) {
        return const RandomGroupFailure(
          'Only the group creator can delete the group',
          RandomGroupErrorType.notAuthorized,
        );
      }

      // Set group to inactive (soft delete)
      await _groupsRef.doc(groupId).update({
        'status': 'inactive',
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      _logger.i('Deleted group $groupId');
      return const RandomGroupSuccess(null);
    } on FirebaseException catch (e, stack) {
      _logger.e('Error deleting group', error: e, stackTrace: stack);
      final dbException = _mapFirestoreException(e);
      return RandomGroupFailure(
        dbException.message,
        e.code == 'permission-denied'
            ? RandomGroupErrorType.notAuthorized
            : RandomGroupErrorType.networkError,
      );
    } catch (e, stack) {
      _logger.e('Error deleting group', error: e, stackTrace: stack);
      return RandomGroupFailure(
        'Failed to delete group: $e',
        RandomGroupErrorType.unknown,
      );
    }
  }
}
