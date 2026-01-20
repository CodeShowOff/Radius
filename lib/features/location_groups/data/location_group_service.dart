import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final FirebaseAuth _auth;
  final Logger _logger;
  final Uuid _uuid;

  // Collection references
  late final CollectionReference<Map<String, dynamic>> _groupsRef;

  LocationGroupService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _logger = logger ?? Logger(),
        _uuid = const Uuid() {
    _groupsRef = _firestore.collection('location_groups');
  }

  bool _canAccessUserScopedData(String userId) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      _logger.w('Skipped user-scoped group query because no authenticated user');
      return false;
    }
    if (currentUserId != userId) {
      _logger.w('Skipped user-scoped group query for mismatched userId (requested: $userId, auth: $currentUserId)');
      return false;
    }
    return true;
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
        unreadCount: 0,
        lastReadAt: now,
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
  /// 
  /// Note: This query requires a composite Firestore index on:
  /// (countryCode, stateCode, status, lastActivityAt/createdAt/memberCount)
  /// 
  /// If the index doesn't exist, the stream will emit an error.
  /// The error is logged but NOT converted to an empty list, so that
  /// the BLoC can preserve any previously loaded data.
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
    }).handleError((error, stackTrace) {
      // Log the error but don't transform it - let it propagate to the BLoC
      // The BLoC will handle the error and preserve existing data
      _logger.e('Error in streamGroupsForLocation stream', error: error);
      // Check if this is a missing index error and log more details
      if (error.toString().contains('FAILED_PRECONDITION') ||
          error.toString().contains('requires an index')) {
        _logger.w(
          'Firestore index missing! Deploy the index using: firebase deploy --only firestore:indexes',
        );
      }
      throw error; // Re-throw to let BLoC handle it
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
  /// 
  /// Errors are logged but re-thrown to let the BLoC preserve existing data.
  Stream<LocationGroup?> streamGroup(String groupId) {
    return _groupsRef.doc(groupId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return LocationGroupModel.fromFirestore(doc);
    }).handleError((error, stackTrace) {
      _logger.e('Error in streamGroup', error: error);
      throw error; // Re-throw to let BLoC handle it
    });
  }

  /// Gets groups the user is a member of.
  Future<List<LocationGroup>> getUserGroups(String userId) async {
    if (!_canAccessUserScopedData(userId)) {
      return [];
    }

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
      final groupIds = membershipQuery.docs
          .where((doc) => doc.reference.parent.parent != null)
          .map((doc) {
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

  /// Waits for the auth token to be available and valid.
  /// 
  /// This prevents race conditions where Firestore queries are executed
  /// before the auth token has propagated to the Firebase SDK.
  Future<bool> _waitForAuthToken(String userId, {int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      final currentUser = _auth.currentUser;
      if (currentUser != null && currentUser.uid == userId) {
        try {
          // Force token refresh to ensure it's valid
          final token = await currentUser.getIdToken(false);
          if (token != null && token.isNotEmpty) {
            return true;
          }
        } catch (e) {
          _logger.w('Token validation failed on attempt ${i + 1}', error: e);
        }
      }
      // Wait briefly before retry
      if (i < maxRetries - 1) {
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }
    _logger.e('Failed to validate auth token after $maxRetries attempts');
    return false;
  }

  /// Streams groups the user is a member of.
  ///
  /// IMPORTANT: This uses a collection group query which requires:
  /// 1. A Firestore security rule at /{path=**}/members/{memberId}
  /// 2. The user to be authenticated with a valid token
  ///
  /// Returns empty stream if user is not authenticated or userId doesn't match.
  /// Errors are caught and logged, returning empty list to prevent UI disruption.
  Stream<List<LocationGroup>> streamUserGroups(String userId) {
    // Validate auth synchronously first
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      _logger.w('streamUserGroups: No auth or userId mismatch (auth: ${currentUser?.uid}, requested: $userId)');
      return Stream.value(<LocationGroup>[]);
    }

    // Create a controller to handle the async token validation
    final controller = StreamController<List<LocationGroup>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    bool isDisposed = false;

    // Start the stream after validating the auth token
    () async {
      // Wait for auth token to be ready
      final isAuthReady = await _waitForAuthToken(userId);
      if (!isAuthReady || isDisposed) {
        if (!isDisposed) {
          _logger.w('streamUserGroups: Auth token not ready, emitting empty list');
          controller.add(<LocationGroup>[]);
          await controller.close();
        }
        return;
      }

      subscription = _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen(
        (snapshot) async {
          if (isDisposed) return;
          
          try {
            // Re-validate auth on each emission
            final user = _auth.currentUser;
            if (user == null || user.uid != userId) {
              _logger.w('streamUserGroups: Auth invalidated during stream');
              controller.add(<LocationGroup>[]);
              return;
            }

            if (snapshot.docs.isEmpty) {
              controller.add(<LocationGroup>[]);
              return;
            }

            final groupIds = snapshot.docs
                .where((doc) => doc.reference.parent.parent != null)
                .map((doc) => doc.reference.parent.parent!.id)
                .toSet();

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

            if (!isDisposed) {
              controller.add(groups);
            }
          } catch (e) {
            _logger.e('Error processing streamUserGroups snapshot', error: e);
            if (!isDisposed) {
              controller.add(<LocationGroup>[]);
            }
          }
        },
        onError: (error) {
          _logger.e('Error in streamUserGroups stream', error: error);
          // Check if this is a permission error
          if (error.toString().contains('permission-denied') ||
              error.toString().contains('PERMISSION_DENIED')) {
            _logger.w(
              'PERMISSION_DENIED in streamUserGroups - check Firestore rules for collectionGroup members',
            );
          }
          // Emit empty list on error instead of propagating
          if (!isDisposed) {
            controller.add(<LocationGroup>[]);
          }
        },
      );
    }();

    // Handle cleanup when the stream is cancelled
    controller.onCancel = () {
      isDisposed = true;
      subscription?.cancel();
    };

    return controller.stream;
  }

  /// Streams the user's memberships (for unread counts).
  ///
  /// IMPORTANT: This uses a collection group query which requires:
  /// 1. A Firestore security rule at /{path=**}/members/{memberId}
  /// 2. The user to be authenticated with a valid token
  ///
  /// Returns empty stream if user is not authenticated or userId doesn't match.
  Stream<List<GroupMembership>> streamUserMemberships(String userId) {
    // Validate auth synchronously first
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      _logger.w('streamUserMemberships: No auth or userId mismatch (auth: ${currentUser?.uid}, requested: $userId)');
      return Stream.value(<GroupMembership>[]);
    }

    // Create a controller to handle the async token validation
    final controller = StreamController<List<GroupMembership>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    bool isDisposed = false;

    // Start the stream after validating the auth token
    () async {
      // Wait for auth token to be ready
      final isAuthReady = await _waitForAuthToken(userId);
      if (!isAuthReady || isDisposed) {
        if (!isDisposed) {
          _logger.w('streamUserMemberships: Auth token not ready, emitting empty list');
          controller.add(<GroupMembership>[]);
          await controller.close();
        }
        return;
      }

      subscription = _firestore
          .collectionGroup('members')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen(
        (snapshot) {
          if (isDisposed) return;
          
          try {
            // Re-validate auth on each emission
            final user = _auth.currentUser;
            if (user == null || user.uid != userId) {
              _logger.w('streamUserMemberships: Auth invalidated during stream');
              controller.add(<GroupMembership>[]);
              return;
            }

            final memberships = snapshot.docs
                .where((doc) => doc.reference.parent.parent != null)
                .map((doc) {
              final groupId = doc.reference.parent.parent!.id;
              return GroupMembershipModel.fromFirestore(doc, groupId);
            }).toList();

            if (!isDisposed) {
              controller.add(memberships);
            }
          } catch (e) {
            _logger.e('Error processing streamUserMemberships snapshot', error: e);
            if (!isDisposed) {
              controller.add(<GroupMembership>[]);
            }
          }
        },
        onError: (error) {
          _logger.e('Error in streamUserMemberships stream', error: error);
          // Check if this is a permission error
          if (error.toString().contains('permission-denied') ||
              error.toString().contains('PERMISSION_DENIED')) {
            _logger.w(
              'PERMISSION_DENIED in streamUserMemberships - check Firestore rules for collectionGroup members',
            );
          }
          // Emit empty list on error instead of propagating
          if (!isDisposed) {
            controller.add(<GroupMembership>[]);
          }
        },
      );
    }();

    // Handle cleanup when the stream is cancelled
    controller.onCancel = () {
      isDisposed = true;
      subscription?.cancel();
    };

    return controller.stream;
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
        unreadCount: 0,
        lastReadAt: DateTime.now(),
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
      
      // Provide more specific error messages based on Firebase error codes
      String errorMessage = 'Failed to join group';
      GroupErrorType errorType = GroupErrorType.networkError;
      
      switch (e.code) {
        case 'permission-denied':
          errorMessage = 'You don\'t have permission to join this group';
          errorType = GroupErrorType.notAuthorized;
          break;
        case 'not-found':
          errorMessage = 'Group not found';
          errorType = GroupErrorType.notFound;
          break;
        case 'unavailable':
          errorMessage = 'Network error. Please check your connection and try again';
          errorType = GroupErrorType.networkError;
          break;
        default:
          errorMessage = 'Failed to join group: ${e.message ?? e.code}';
          errorType = GroupErrorType.networkError;
      }
      
      return GroupFailure(errorMessage, errorType);
    } catch (e) {
      _logger.e('Error joining group', error: e);
      return GroupFailure(
        'An unexpected error occurred: ${e.toString()}',
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
      
      // Provide more specific error messages
      String errorMessage = 'Failed to send request';
      GroupErrorType errorType = GroupErrorType.networkError;
      
      switch (e.code) {
        case 'permission-denied':
          errorMessage = 'You don\'t have permission to request to join this group';
          errorType = GroupErrorType.notAuthorized;
          break;
        case 'not-found':
          errorMessage = 'Group not found';
          errorType = GroupErrorType.notFound;
          break;
        case 'unavailable':
          errorMessage = 'Network error. Please check your connection and try again';
          errorType = GroupErrorType.networkError;
          break;
        default:
          errorMessage = 'Failed to send request: ${e.message ?? e.code}';
          errorType = GroupErrorType.networkError;
      }
      
      return GroupFailure(errorMessage, errorType);
    } catch (e) {
      _logger.e('Error requesting to join', error: e);
      return GroupFailure(
        'An unexpected error occurred: ${e.toString()}',
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
        unreadCount: 0,
        lastReadAt: DateTime.now(),
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
      try {
        return snapshot.docs
            .map((doc) => GroupJoinRequestModel.fromFirestore(doc, groupId))
            .toList();
      } catch (e) {
        _logger.e('Error in streamJoinRequests map', error: e);
        return <GroupJoinRequest>[];
      }
    }).transform(StreamTransformer.fromHandlers(
      handleError: (error, stackTrace, sink) {
        // On error, emit empty list to ensure UI receives data
        _logger.e('Error in streamJoinRequests, emitting empty list', error: error);
        sink.add(<GroupJoinRequest>[]);
      },
    ));
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
      try {
        return snapshot.docs
            .map((doc) => GroupMembershipModel.fromFirestore(doc, groupId))
            .toList();
      } catch (e) {
        _logger.e('Error in streamGroupMembers map', error: e);
        return <GroupMembership>[];
      }
    }).transform(StreamTransformer.fromHandlers(
      handleError: (error, stackTrace, sink) {
        // On error, emit empty list to ensure UI receives data
        _logger.e('Error in streamGroupMembers, emitting empty list', error: error);
        sink.add(<GroupMembership>[]);
      },
    ));
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
    String? avatarUrl,
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

      if (avatarUrl != null) {
        updates['avatarUrl'] = avatarUrl;
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

  /// Deletes a group permanently (admin only).
  /// This will delete the group document and all subcollections.
  Future<GroupResult<void>> deleteGroup({
    required String groupId,
    required String adminUserId,
  }) async {
    try {
      final callerMembership = await _getMembership(groupId, adminUserId);
      if (callerMembership == null || !callerMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can delete groups',
          GroupErrorType.notAuthorized,
        );
      }

      await _deleteSubcollection(groupId, 'join_requests');
      // NOTE: Group messages are soft-deleted by design (see Firestore rules).
      // Hard-deleting message documents from clients is not permitted.

      // Delete members, but keep the admin membership until the very end.
      // Otherwise subsequent admin-gated operations (including group delete)
      // can fail with permission-denied.
      await _deleteSubcollection(
        groupId,
        'members',
        skipDocIds: {adminUserId},
      );

      // Delete the group document itself
      await _groupsRef.doc(groupId).delete();

      // Finally delete the admin membership doc.
      // This is allowed because the admin is deleting their own member doc.
      await _groupsRef.doc(groupId).collection('members').doc(adminUserId).delete();

      _logger.i('Group $groupId deleted by admin $adminUserId');
      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error deleting group', error: e);
      return const GroupFailure(
        'Failed to delete group',
        GroupErrorType.unknown,
      );
    }
  }

  /// Clears all messages in a group (admin only).
  Future<GroupResult<void>> clearGroupMessages({
    required String groupId,
    required String adminUserId,
  }) async {
    try {
      final callerMembership = await _getMembership(groupId, adminUserId);
      if (callerMembership == null || !callerMembership.isAdmin) {
        return const GroupFailure(
          'Only admins can clear chat',
          GroupErrorType.notAuthorized,
        );
      }

      await _softDeleteGroupMessages(groupId);

      await _groupsRef.doc(groupId).update({
        'lastActivityAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': null,
      });

      return const GroupSuccess(null);
    } catch (e) {
      _logger.e('Error clearing group messages', error: e);
      return const GroupFailure(
        'Failed to clear chat',
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

  Future<void> _deleteSubcollection(
    String groupId,
    String subcollection, {
    int batchSize = 400,
    Set<String> skipDocIds = const {},
  }) async {
    final collectionRef = _groupsRef.doc(groupId).collection(subcollection);

    while (true) {
      final snapshot = await collectionRef.limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final docsToDelete = snapshot.docs.where((d) => !skipDocIds.contains(d.id)).toList();
      if (docsToDelete.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in docsToDelete) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.size < batchSize) break;
    }
  }

  Future<void> _softDeleteGroupMessages(
    String groupId, {
    int batchSize = 400,
  }) async {
    final collectionRef = _groupsRef.doc(groupId).collection('messages');

    while (true) {
      final snapshot = await collectionRef
          .where('isDeleted', isEqualTo: false)
          .limit(batchSize)
          .get();

      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, const {'isDeleted': true});
      }
      await batch.commit();

      if (snapshot.size < batchSize) break;
    }
  }
}
