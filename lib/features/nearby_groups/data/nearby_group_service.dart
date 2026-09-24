import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/exceptions.dart';
import '../../proximity/domain/entities/nearby_user.dart';
import '../domain/entities/nearby_group.dart';
import '../domain/entities/nearby_group_member.dart';
import 'models/nearby_group_model.dart';
import 'models/nearby_group_member_model.dart';

/// Result type for nearby group operations.
sealed class NearbyGroupResult<T> {
  const NearbyGroupResult();
}

class NearbyGroupSuccess<T> extends NearbyGroupResult<T> {
  final T data;
  const NearbyGroupSuccess(this.data);
}

class NearbyGroupFailure<T> extends NearbyGroupResult<T> {
  final String message;
  final NearbyGroupErrorType type;
  const NearbyGroupFailure(this.message, this.type);
}

enum NearbyGroupErrorType {
  alreadyHasActiveGroup,
  notFound,
  notAuthorized,
  invalidData,
  networkError,
  unknown,
}

/// Service for managing Bluetooth-based nearby groups.
///
/// Firestore Collections:
/// - `nearby_groups` - Group metadata
/// - `nearby_groups/{groupId}/members` - Current nearby members
/// - `nearby_groups/{groupId}/messages` - Group chat messages
///
/// Key behaviors:
/// - Only one active group per user at a time
/// - Creator's device scans for nearby users and updates member list
/// - Members are auto-added/removed based on Bluetooth discovery
/// - Group becomes inactive when creator stops scanning
class NearbyGroupService {
  final FirebaseFirestore _firestore;
  final Logger _logger;
  final Uuid _uuid;

  late final CollectionReference<Map<String, dynamic>> _groupsRef;

  /// Duration after which a member is considered "gone" (10 seconds)
  static const Duration memberTimeout = Duration(seconds: 10);

  /// Duration after which a group is considered "inactive" (15 seconds)
  static const Duration groupInactiveTimeout = Duration(seconds: 15);

  NearbyGroupService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger(),
        _uuid = const Uuid() {
    _groupsRef = _firestore.collection('nearby_groups');
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

  /// Creates a new nearby group.
  ///
  /// Validates:
  /// - User doesn't already have an active group
  /// - Name is valid
  Future<NearbyGroupResult<NearbyGroup>> createGroup({
    required String name,
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
        return const NearbyGroupFailure(
          'Group name must be at least 2 characters',
          NearbyGroupErrorType.invalidData,
        );
      }
      if (trimmedName.length > 50) {
        return const NearbyGroupFailure(
          'Group name must be 50 characters or less',
          NearbyGroupErrorType.invalidData,
        );
      }

      // Check if user already has an active group
      final existingGroups = await _groupsRef
          .where('creatorId', isEqualTo: creatorId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (existingGroups.docs.isNotEmpty) {
        return const NearbyGroupFailure(
          'You already have an active nearby group. Close it first to create a new one.',
          NearbyGroupErrorType.alreadyHasActiveGroup,
        );
      }

      // Create group document
      final groupId = _uuid.v4();
      final group = NearbyGroupModel.create(
        id: groupId,
        name: trimmedName,
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

      // Add creator as first member
      final creatorMember = NearbyGroupMemberModel.create(
        userId: creatorId,
        username: creatorUsername,
        displayName: creatorDisplayName,
        photoUrl: creatorPhotoUrl,
        rssi: 0, // Creator is always "very close" to themselves
      );
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(creatorId),
        creatorMember.toFirestore(useServerTimestamp: true),
      );

      await batch.commit();

      _logger.i('Created nearby group: $groupId with name: $trimmedName');
      return NearbyGroupSuccess(group.toEntity());
    } on FirebaseException catch (e, stack) {
      _logger.e('Error creating nearby group', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error creating nearby group', error: e, stackTrace: stack);
      return NearbyGroupFailure(
        'Failed to create group: $e',
        NearbyGroupErrorType.unknown,
      );
    }
  }

  // ==================== GROUP MANAGEMENT ====================

  /// Closes a nearby group (sets it to inactive).
  /// Only the creator can close their group.
  Future<void> closeGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        throw const DatabaseException(
          message: 'Group not found',
          code: 'not-found',
        );
      }

      final creatorId = groupDoc.data()?['creatorId'] as String?;
      if (creatorId != userId) {
        throw const DatabaseException(
          message: 'Only the group creator can close the group',
          code: 'permission-denied',
        );
      }

      await _groupsRef.doc(groupId).update({
        'status': 'inactive',
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      _logger.i('Closed nearby group: $groupId');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error closing nearby group', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    }
  }

  /// Deletes a nearby group entirely including all members and messages.
  /// Only the creator can delete their group.
  Future<void> deleteGroup({
    required String groupId,
    required String userId,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        throw const DatabaseException(
          message: 'Group not found',
          code: 'not-found',
        );
      }

      final creatorId = groupDoc.data()?['creatorId'] as String?;
      if (creatorId != userId) {
        throw const DatabaseException(
          message: 'Only the group creator can delete the group',
          code: 'permission-denied',
        );
      }

      final batch = _firestore.batch();

      // Delete all members
      final members = await _groupsRef.doc(groupId).collection('members').get();
      for (final doc in members.docs) {
        batch.delete(doc.reference);
      }

      // Delete all messages
      final messages = await _groupsRef.doc(groupId).collection('messages').get();
      for (final doc in messages.docs) {
        batch.delete(doc.reference);
      }

      // Delete the group document
      batch.delete(_groupsRef.doc(groupId));

      await batch.commit();

      _logger.i('Deleted nearby group: $groupId with ${members.docs.length} members and ${messages.docs.length} messages');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error deleting nearby group', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    }
  }

  /// Gets a group by ID.
  Future<NearbyGroup?> getGroup(String groupId) async {
    try {
      final doc = await _groupsRef.doc(groupId).get();
      if (!doc.exists) return null;
      return NearbyGroupModel.fromFirestore(doc).toEntity();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error getting nearby group', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    }
  }

  /// Gets the user's active group (if any).
  Future<NearbyGroup?> getUserActiveGroup(String userId) async {
    try {
      final query = await _groupsRef
          .where('creatorId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;
      return NearbyGroupModel.fromFirestore(query.docs.first).toEntity();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error getting user active group', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    }
  }

  // ==================== MEMBER MANAGEMENT ====================

  /// Updates nearby members for a group based on Bluetooth scan results.
  /// This should be called by the group creator's device.
  ///
  /// [nearbyUsers] - List of users detected via Bluetooth scan
  /// [groupId] - The group to update
  /// [creatorId] - The creator's user ID (for validation)
  Future<void> updateNearbyMembers({
    required String groupId,
    required String creatorId,
    required List<NearbyUser> nearbyUsers,
  }) async {
    try {
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        _logger.w('Cannot update members: group $groupId not found');
        return;
      }

      final docCreatorId = groupDoc.data()?['creatorId'] as String?;
      if (docCreatorId != creatorId) {
        _logger.w('Cannot update members: user is not the group creator');
        return;
      }

      final batch = _firestore.batch();
      final membersRef = _groupsRef.doc(groupId).collection('members');
      final now = DateTime.now();

      // Get current members
      final currentMembers = await membersRef.get();
      final currentMemberIds =
          currentMembers.docs.map((d) => d.id).toSet();

      // Track which members we're updating
      final updatedMemberIds = <String>{creatorId}; // Creator always stays

      // Update or add nearby users
      for (final user in nearbyUsers) {
        if (user.userId == null) continue; // Skip users without Firebase ID
        
        updatedMemberIds.add(user.userId!);

        final memberData = {
          'userId': user.userId,
          'username': user.username,
          if (user.displayName != null) 'displayName': user.displayName,
          if (user.photoUrl != null) 'photoUrl': user.photoUrl,
          'rssi': user.rssi,
          'lastSeenAt': FieldValue.serverTimestamp(),
        };

        if (!currentMemberIds.contains(user.userId)) {
          // New member - add joinedAt
          memberData['joinedAt'] = FieldValue.serverTimestamp();
        }

        batch.set(
          membersRef.doc(user.userId),
          memberData,
          SetOptions(merge: true),
        );
      }

      // Remove members who are no longer nearby (except creator)
      for (final doc in currentMembers.docs) {
        if (doc.id == creatorId) continue; // Never remove creator

        final lastSeenAt = (doc.data()['lastSeenAt'] as Timestamp?)?.toDate();
        final isStale = lastSeenAt == null ||
            now.difference(lastSeenAt) > memberTimeout;

        if (!updatedMemberIds.contains(doc.id) && isStale) {
          batch.delete(membersRef.doc(doc.id));
        }
      }

      // Update group's lastActiveAt and member count
      batch.update(_groupsRef.doc(groupId), {
        'lastActiveAt': FieldValue.serverTimestamp(),
        'memberCount': updatedMemberIds.length,
      });

      await batch.commit();

      _logger.t('Updated nearby members for group $groupId: ${updatedMemberIds.length} members');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error updating nearby members', error: e, stackTrace: stack);
      // Don't throw - this is called frequently during scanning
    }
  }

  /// Updates the group's heartbeat (lastActiveAt) without changing members.
  /// Call this periodically to indicate the creator is still scanning.
  Future<void> heartbeat({
    required String groupId,
    required String creatorId,
  }) async {
    try {
      await _groupsRef.doc(groupId).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      _logger.w('Heartbeat failed for group $groupId: ${e.code}');
    }
  }

  // ==================== DISCOVERY STREAMS ====================

  /// Stream of all active nearby groups (for discovery).
  /// Only returns groups that have been active within the timeout period.
  Stream<List<NearbyGroup>> watchActiveGroups() {
    return _groupsRef
        .where('status', isEqualTo: 'active')
        .orderBy('lastActiveAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .map((doc) => NearbyGroupModel.fromFirestore(doc).toEntity())
          .where((group) => now.difference(group.lastActiveAt) <= groupInactiveTimeout)
          .toList();
    });
  }

  /// Stream of groups the user is currently a member of.
  /// 
  /// This queries the user's membership documents directly and then
  /// fetches the group details for each active membership.
  Stream<List<NearbyGroup>> watchUserMemberships(String userId) {
    // Query active groups and check if user is a member of each
    // This is more efficient than collectionGroup query
    return _groupsRef
        .where('status', isEqualTo: 'active')
        .orderBy('lastActiveAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      final groups = <NearbyGroup>[];
      final now = DateTime.now();
      
      for (final doc in snapshot.docs) {
        // Skip stale groups
        final group = NearbyGroupModel.fromFirestore(doc).toEntity();
        if (now.difference(group.lastActiveAt) > groupInactiveTimeout) {
          continue;
        }
        
        // Skip groups where user is the creator (handled separately as myActiveGroup)
        if (group.creatorId == userId) {
          continue;
        }
        
        // Check if user is a member
        final memberDoc = await _groupsRef
            .doc(doc.id)
            .collection('members')
            .doc(userId)
            .get();
        
        if (memberDoc.exists) {
          groups.add(group);
        }
      }
      
      return groups;
    });
  }

  /// Stream of a specific group's details.
  Stream<NearbyGroup?> watchGroup(String groupId) {
    return _groupsRef.doc(groupId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return NearbyGroupModel.fromFirestore(doc).toEntity();
    });
  }

  /// Stream of members in a group.
  Stream<List<NearbyGroupMember>> watchGroupMembers(String groupId) {
    return _groupsRef
        .doc(groupId)
        .collection('members')
        .orderBy('lastSeenAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NearbyGroupMemberModel.fromFirestore(doc).toEntity())
          .toList();
    });
  }

  // ==================== CLEANUP ====================

  /// Cleans up stale groups (called periodically or on app start).
  /// Groups that haven't been active for more than the timeout are marked inactive.
  Future<void> cleanupStaleGroups() async {
    try {
      final cutoff = DateTime.now().subtract(groupInactiveTimeout);
      final staleGroups = await _groupsRef
          .where('status', isEqualTo: 'active')
          .where('lastActiveAt', isLessThan: Timestamp.fromDate(cutoff))
          .get();

      final batch = _firestore.batch();
      for (final doc in staleGroups.docs) {
        batch.update(doc.reference, {'status': 'inactive'});
      }

      if (staleGroups.docs.isNotEmpty) {
        await batch.commit();
        _logger.i('Cleaned up ${staleGroups.docs.length} stale nearby groups');
      }
    } on FirebaseException catch (e, stack) {
      _logger.w('Error cleaning up stale groups', error: e, stackTrace: stack);
    }
  }
}
