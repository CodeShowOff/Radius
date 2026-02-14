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
      _logger
          .w('Skipped user-scoped group query because no authenticated user');
      return false;
    }
    if (currentUserId != userId) {
      _logger.w(
          'Skipped user-scoped group query for mismatched userId (requested: $userId, auth: $currentUserId)');
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
      // Validate location codes to prevent Firestore invalid_query errors
      if (countryCode.trim().isEmpty || stateCode.trim().isEmpty) {
        return const GroupFailure(
          'Invalid location: country and state codes are required',
          GroupErrorType.invalidData,
        );
      }

      // Validate and sanitize name
      final trimmedName =
          name.trim().replaceAll(RegExp(r'\s+'), ' '); // Normalize whitespace
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

      // Validate name doesn't consist only of special characters
      if (!RegExp(r'[a-zA-Z0-9]').hasMatch(trimmedName)) {
        return const GroupFailure(
          'Group name must contain letters or numbers',
          GroupErrorType.invalidData,
        );
      }

      // Check for duplicate name in same location
      // First try with nameLowercase index for performance
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

      // Fallback: Check for groups without nameLowercase field (legacy data)
      final legacyCheck = await _groupsRef
          .where('countryCode', isEqualTo: countryCode)
          .where('stateCode', isEqualTo: stateCode)
          .where('status', isEqualTo: 'active')
          .get();

      for (final doc in legacyCheck.docs) {
        final data = doc.data();
        final existingName = data['name'] as String?;
        if (existingName?.toLowerCase() == trimmedName.toLowerCase()) {
          return const GroupFailure(
            'A group with this name already exists in this location',
            GroupErrorType.duplicateName,
          );
        }
      }

      // Create group document
      final groupId = _uuid.v4();
      final now = DateTime.now();

      // Sanitize description
      final sanitizedDescription =
          description?.trim().replaceAll(RegExp(r'\s+'), ' ');
      final finalDescription =
          (sanitizedDescription == null || sanitizedDescription.isEmpty)
              ? null
              : sanitizedDescription;

      final group = LocationGroupModel(
        id: groupId,
        name: trimmedName,
        description: finalDescription,
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

      // Batch write: group + membership + inverse index
      final batch = _firestore.batch();
      batch.set(_groupsRef.doc(groupId), group.toCreateData());
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(creatorUserId),
        membership.toCreateData(),
      );
      // Inverse index for fast user groups query
      batch.set(
        _firestore
            .collection('users')
            .doc(creatorUserId)
            .collection('group_memberships')
            .doc(groupId),
        {
          'groupId': groupId,
          'userId': creatorUserId,
          'role': 'admin',
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
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
    // Validate inputs to prevent Firestore invalid_query errors
    if (countryCode.trim().isEmpty || stateCode.trim().isEmpty) {
      _logger
          .w('getGroupsForLocation called with empty countryCode or stateCode');
      return [];
    }

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
    // Validate inputs to prevent Firestore invalid_query errors
    if (countryCode.trim().isEmpty || stateCode.trim().isEmpty) {
      _logger.w(
          'streamGroupsForLocation called with empty countryCode or stateCode');
      return Stream.value([]);
    }

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
  ///
  /// PERFORMANCE: Uses inverse index users/{userId}/group_memberships
  /// instead of slow collection group query.
  Future<List<LocationGroup>> getUserGroups(String userId) async {
    if (!_canAccessUserScopedData(userId)) {
      return [];
    }

    try {
      // Query inverse index - MUCH faster than collection group
      final membershipQuery = await _firestore
          .collection('users')
          .doc(userId)
          .collection('group_memberships')
          .where('status', isEqualTo: 'active')
          .get();

      if (membershipQuery.docs.isEmpty) return [];

      // Get group IDs from inverse index
      final groupIds = membershipQuery.docs
          .map((doc) => doc.data()['groupId'] as String)
          .toSet()
          .toList();

      // Batch fetch groups using whereIn (max 10 per query) instead of
      // individual get calls. Reduces N round-trips to ceil(N/10).
      final groups = await _batchFetchGroups(groupIds);

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
      _logger.w(
          'streamUserGroups: No auth or userId mismatch (auth: ${currentUser?.uid}, requested: $userId)');
      return Stream.value(<LocationGroup>[]);
    }

    // Create a controller to pipe the Firestore stream
    final controller = StreamController<List<LocationGroup>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    bool isDisposed = false;

    // Start the stream immediately — auth token is already validated by
    // RealTimeDataManager before LoadUserGroups is dispatched.
    // No redundant _waitForAuthToken() call here.
    () async {
      // Use inverse index - MUCH faster than collection group query
      subscription = _firestore
          .collection('users')
          .doc(userId)
          .collection('group_memberships')
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

            // Get group IDs from inverse index
            final groupIds = snapshot.docs
                .map((doc) => doc.data()['groupId'] as String)
                .toSet()
                .toList();

            // Batch fetch groups using whereIn (max 10 per query) instead of
            // individual getGroupById calls. This reduces N network round-trips
            // to ceil(N/10), dramatically improving load time.
            final groups = await _batchFetchGroups(groupIds);

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

  /// Streams the user's memberships across all groups.
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
      _logger.w(
          'streamUserMemberships: No auth or userId mismatch (auth: ${currentUser?.uid}, requested: $userId)');
      return Stream.value(<GroupMembership>[]);
    }

    // Create a controller to pipe the Firestore stream
    final controller = StreamController<List<GroupMembership>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subscription;
    bool isDisposed = false;

    // Start the stream immediately — auth token is already validated by
    // RealTimeDataManager before LoadUserGroups is dispatched.
    () async {
      // Use inverse index - MUCH faster than collection group query
      subscription = _firestore
          .collection('users')
          .doc(userId)
          .collection('group_memberships')
          .where('status', isEqualTo: 'active')
          .snapshots()
          .listen(
        (snapshot) async {
          if (isDisposed) return;

          try {
            // Re-validate auth on each emission
            final user = _auth.currentUser;
            if (user == null || user.uid != userId) {
              _logger
                  .w('streamUserMemberships: Auth invalidated during stream');
              controller.add(<GroupMembership>[]);
              return;
            }

            // Fetch full membership details in PARALLEL instead of sequentially.
            // Each _getMembership call is independent, so Future.wait eliminates
            // the sequential delay (N * latency → max(latencies)).
            final membershipFutures = snapshot.docs.map((doc) {
              final groupId = doc.data()['groupId'] as String;
              return _getMembership(groupId, userId);
            });
            final results = await Future.wait(membershipFutures);
            final memberships = results
                .whereType<GroupMembership>()
                .toList();

            if (!isDisposed) {
              controller.add(memberships);
            }
          } catch (e) {
            _logger.e('Error processing streamUserMemberships snapshot',
                error: e);
            if (!isDisposed) {
              controller.add(<GroupMembership>[]);
            }
          }
        },
        onError: (error) {
          _logger.e('Error in streamUserMemberships stream', error: error);
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
      );

      // RISK MITIGATION: Use batch for atomic writes (prevents member count desync)
      // If any operation fails, entire batch is rolled back
      final batch = _firestore.batch();
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(userId),
        membership.toCreateData(),
      );
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Inverse index for fast user groups query
      batch.set(
        _firestore
            .collection('users')
            .doc(userId)
            .collection('group_memberships')
            .doc(groupId),
        {
          'groupId': groupId,
          'userId': userId,
          'role': 'member',
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      try {
        await batch.commit();
        _logger.i('User $userId joined group $groupId');
      } catch (batchError) {
        _logger.e('Batch commit failed for joinPublicGroup', error: batchError);
        // Batch is atomic - if it fails, no partial writes occurred
        rethrow;
      }

      // CRITICAL FIX: Send system message with delay to allow Firestore replication
      // This prevents permission-denied errors when user tries to send first message
      try {
        final displayName = userName ?? 'Someone';
        await sendSystemMessage(
          groupId: groupId,
          text: '$displayName joined the group',
          delayBeforeSend: true, // Wait for replication
        );
      } catch (e) {
        _logger.w('Failed to send join system message', error: e);
        // Don't fail the join operation if system message fails
      }

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
          errorMessage =
              'Network error. Please check your connection and try again';
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
      // Sanitize and validate message
      final sanitizedMessage = message?.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (sanitizedMessage != null && sanitizedMessage.length > 200) {
        return const GroupFailure(
          'Request message must be 200 characters or less',
          GroupErrorType.invalidData,
        );
      }

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
        message: sanitizedMessage,
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
          errorMessage =
              'You don\'t have permission to request to join this group';
          errorType = GroupErrorType.notAuthorized;
          break;
        case 'not-found':
          errorMessage = 'Group not found';
          errorType = GroupErrorType.notFound;
          break;
        case 'unavailable':
          errorMessage =
              'Network error. Please check your connection and try again';
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
      );

      // RISK MITIGATION: Atomic batch ensures request cleanup + membership creation
      // This prevents orphaned join requests
      final batch = _firestore.batch();
      batch.set(
        _groupsRef.doc(groupId).collection('members').doc(requestUserId),
        membership.toCreateData(),
      );
      batch.delete(requestDoc.reference); // Clean up join request atomically
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Inverse index for fast user groups query
      batch.set(
        _firestore
            .collection('users')
            .doc(requestUserId)
            .collection('group_memberships')
            .doc(groupId),
        {
          'groupId': groupId,
          'userId': requestUserId,
          'role': 'member',
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      try {
        await batch.commit();
      } catch (batchError) {
        _logger.e('Batch commit failed for approveJoinRequest',
            error: batchError);

        // Check for permission errors specifically
        if (batchError is FirebaseException) {
          if (batchError.code == 'permission-denied') {
            return const GroupFailure(
              'Permission denied. Please check group admin status.',
              GroupErrorType.notAuthorized,
            );
          }
        }

        // Atomic rollback - request not deleted if membership creation failed
        rethrow;
      }

      _logger
          .i('Admin $adminUserId approved $requestUserId for group $groupId');

      // Send system message with delay for replication
      try {
        final displayName = requestData['userName'] as String? ?? 'Someone';
        await sendSystemMessage(
          groupId: groupId,
          text: '$displayName joined the group',
          delayBeforeSend: true,
        );
      } catch (e) {
        _logger.w('Failed to send join system message', error: e);
      }

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

      _logger
          .i('Admin $adminUserId rejected $requestUserId for group $groupId');
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
        _logger.e('Error in streamJoinRequests, emitting empty list',
            error: error);
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

      // RISK MITIGATION: Atomic batch prevents partial state (member count desync)
      final batch = _firestore.batch();
      batch.update(
        _groupsRef.doc(groupId).collection('members').doc(userId),
        {
          'status': 'left',
          'leftAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Remove from inverse index
      batch.delete(
        _firestore
            .collection('users')
            .doc(userId)
            .collection('group_memberships')
            .doc(groupId),
      );

      try {
        await batch.commit();
        _logger.i('User $userId left group $groupId');
      } catch (batchError) {
        _logger.e('Batch commit failed for leaveGroup', error: batchError);
        // All-or-nothing: prevents memberCount decrement without membership update
        return GroupFailure(
          'Failed to leave group. Please try again.',
          GroupErrorType.unknown,
        );
      }

      // Send system message
      try {
        final displayName = membership.userName ?? 'Someone';
        await sendSystemMessage(
          groupId: groupId,
          text: '$displayName left the group',
        );
      } catch (e) {
        _logger.w('Failed to send leave system message', error: e);
      }

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
        _logger.e('Error in streamGroupMembers, emitting empty list',
            error: error);
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

      // Update both membership and inverse index
      final batch = _firestore.batch();
      batch.update(
        _groupsRef.doc(groupId).collection('members').doc(targetUserId),
        {
          'role': 'admin',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      // Update inverse index
      batch.update(
        _firestore
            .collection('users')
            .doc(targetUserId)
            .collection('group_memberships')
            .doc(groupId),
        {
          'role': 'admin',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();

      _logger.i('User $targetUserId promoted to admin in group $groupId');

      // Send system message
      try {
        final displayName = targetMembership.userName ?? 'Someone';
        await sendSystemMessage(
          groupId: groupId,
          text: '$displayName was promoted to admin',
        );
      } catch (e) {
        _logger.w('Failed to send promotion system message', error: e);
      }

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

      // Verify target is an active member
      final targetMembership = await _getMembership(groupId, targetUserId);
      if (targetMembership == null || !targetMembership.isActive) {
        return const GroupFailure(
          'User is not an active member of this group',
          GroupErrorType.notFound,
        );
      }

      // RISK MITIGATION: Atomic batch for removal (prevents count desync)
      final batch = _firestore.batch();
      batch.update(
        _groupsRef.doc(groupId).collection('members').doc(targetUserId),
        {
          'status': ban ? 'banned' : 'left',
          'note': reason,
          'removedBy': adminUserId,
          'removedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.update(_groupsRef.doc(groupId), {
        'memberCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Remove from inverse index (whether banned or removed)
      batch.delete(
        _firestore
            .collection('users')
            .doc(targetUserId)
            .collection('group_memberships')
            .doc(groupId),
      );

      try {
        await batch.commit();
        _logger.i(
            'User $targetUserId ${ban ? "banned from" : "removed from"} group $groupId');
      } catch (batchError) {
        _logger.e('Batch commit failed for removeMember', error: batchError);
        return GroupFailure(
          'Failed to remove member. Please try again.',
          GroupErrorType.unknown,
        );
      }

      // Send system message
      try {
        final targetMembership = await _getMembership(groupId, targetUserId);
        final displayName = targetMembership?.userName ?? 'A member';
        await sendSystemMessage(
          groupId: groupId,
          text: ban ? '$displayName was banned' : '$displayName was removed',
        );
      } catch (e) {
        _logger.w('Failed to send removal system message', error: e);
      }

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
        final trimmedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (trimmedName.length < 3 || trimmedName.length > 50) {
          return const GroupFailure(
            'Group name must be 3-50 characters',
            GroupErrorType.invalidData,
          );
        }

        if (!RegExp(r'[a-zA-Z0-9]').hasMatch(trimmedName)) {
          return const GroupFailure(
            'Group name must contain letters or numbers',
            GroupErrorType.invalidData,
          );
        }

        // Check for duplicate name in same location
        final group = await getGroupById(groupId);
        if (group != null) {
          // Validate location codes are present (defensive check)
          if (group.countryCode.trim().isEmpty ||
              group.stateCode.trim().isEmpty) {
            _logger.e(
                'Group $groupId has invalid location codes, cannot check for duplicates');
            return const GroupFailure(
              'Group has invalid location data',
              GroupErrorType.invalidData,
            );
          }

          // First try with nameLowercase index
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

          // Fallback: Check for groups without nameLowercase field (legacy data)
          final legacyCheck = await _groupsRef
              .where('countryCode', isEqualTo: group.countryCode)
              .where('stateCode', isEqualTo: group.stateCode)
              .where('status', isEqualTo: 'active')
              .get();

          for (final doc in legacyCheck.docs) {
            if (doc.id == groupId) continue; // Skip current group
            final data = doc.data();
            final existingName = data['name'] as String?;
            if (existingName?.toLowerCase() == trimmedName.toLowerCase()) {
              return const GroupFailure(
                'A group with this name already exists in this location',
                GroupErrorType.duplicateName,
              );
            }
          }
        }

        updates['name'] = trimmedName;
        updates['nameLowercase'] = trimmedName.toLowerCase();
      }

      if (description != null) {
        final trimmedDesc = description.trim().replaceAll(RegExp(r'\s+'), ' ');
        updates['description'] = trimmedDesc.isEmpty ? null : trimmedDesc;
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

      // RISK MITIGATION: Clean up orphaned join requests
      _logger.i('Cleaned up join_requests subcollection for group $groupId');

      // Fetch all members BEFORE deleting them so we can clean up inverse indexes
      final membersSnapshot = await _groupsRef
          .doc(groupId)
          .collection('members')
          .get();
      final memberIds = membersSnapshot.docs.map((doc) => doc.id).toList();

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
      await _groupsRef
          .doc(groupId)
          .collection('members')
          .doc(adminUserId)
          .delete();

      // Clean up inverse index entries for ALL members (including admin)
      // so that streamUserGroups fires and removes the group from every user's list.
      // Use batched writes for efficiency (max 450 per batch to stay under Firestore limit).
      const batchLimit = 450;
      for (var i = 0; i < memberIds.length; i += batchLimit) {
        final batch = _firestore.batch();
        final end = (i + batchLimit).clamp(0, memberIds.length);
        for (final memberId in memberIds.sublist(i, end)) {
          batch.delete(
            _firestore
                .collection('users')
                .doc(memberId)
                .collection('group_memberships')
                .doc(groupId),
          );
        }
        try {
          await batch.commit();
        } catch (e) {
          _logger.w('Failed to clean up inverse index batch starting at $i', error: e);
          // Continue with remaining batches even if one fails
        }
      }

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

  /// Sends a system message to the group (e.g., "X joined the group").
  ///
  /// IMPORTANT: Use delayBeforeSend=true when calling immediately after
  /// membership changes to allow Firestore replication.
  Future<void> sendSystemMessage({
    required String groupId,
    required String text,
    bool delayBeforeSend = false,
  }) async {
    try {
      // CRITICAL: Add delay if requested (e.g., after join to allow replication)
      if (delayBeforeSend) {
        _logger.d(
            'Waiting 1s for Firestore replication before sending system message');
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      final messageData = {
        'groupId': groupId,
        'senderId': 'system',
        'text': text,
        'type': 'system',
        'sentAt': FieldValue.serverTimestamp(),
        'status': 'sent',
        'isDeleted': false,
      };

      final batch = _firestore.batch();
      final messageRef = _groupsRef.doc(groupId).collection('messages').doc();
      batch.set(messageRef, messageData);
      batch.update(_groupsRef.doc(groupId), {
        'lastActivityAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': text,
      });
      await batch.commit();
    } catch (e) {
      _logger.e('Error sending system message', error: e);
      // Don't rethrow - system messages are non-critical
    }
  }

  // ==================== RISK MITIGATION METHODS ====================

  /// Updates denormalized user data across all group memberships.
  ///
  /// RISK MITIGATION: Prevents stale user names/avatars in group member lists.
  /// Call this when user updates their profile.
  Future<void> updateMemberProfileData({
    required String userId,
    String? userName,
    String? userPhotoUrl,
  }) async {
    try {
      // Get all groups where user is a member using inverse index
      final membershipsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('group_memberships')
          .where('status', isEqualTo: 'active')
          .get();

      if (membershipsSnapshot.docs.isEmpty) {
        _logger.d('No active memberships to update for user $userId');
        return;
      }

      final groupIds = membershipsSnapshot.docs
          .map((doc) => doc.data()['groupId'] as String)
          .toList();

      // Update denormalized data in batches (max 450 per batch)
      final batches = <WriteBatch>[];
      var currentBatch = _firestore.batch();
      var operationCount = 0;

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (userName != null) updateData['userName'] = userName;
      if (userPhotoUrl != null) updateData['userPhotoUrl'] = userPhotoUrl;

      for (final groupId in groupIds) {
        final memberRef =
            _groupsRef.doc(groupId).collection('members').doc(userId);

        currentBatch.update(memberRef, updateData);
        operationCount++;

        if (operationCount >= 450) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
        }
      }

      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      // Commit all batches
      for (final batch in batches) {
        await batch.commit();
      }

      _logger.i(
          'Updated denormalized profile data for user $userId across ${groupIds.length} groups');
    } catch (e) {
      _logger.e('Error updating member profile data', error: e);
      // Don't throw - this is a background operation
    }
  }

  /// Recalculates and fixes member count for a group.
  ///
  /// RISK MITIGATION: Repairs member count desync caused by failed transactions.
  /// Run this as a background job or admin tool if counts appear incorrect.
  Future<void> repairMemberCount(String groupId) async {
    try {
      // Count actual active members
      final membersSnapshot = await _groupsRef
          .doc(groupId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .get();

      final actualCount = membersSnapshot.docs.length;

      // Get current stored count
      final groupDoc = await _groupsRef.doc(groupId).get();
      if (!groupDoc.exists) {
        _logger.w('Cannot repair member count - group $groupId not found');
        return;
      }

      final currentCount = groupDoc.data()?['memberCount'] as int? ?? 0;

      if (actualCount != currentCount) {
        _logger.w(
          'Member count mismatch for group $groupId: stored=$currentCount, actual=$actualCount. Repairing...',
        );

        await _groupsRef.doc(groupId).update({
          'memberCount': actualCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _logger.i(
            'Repaired member count for group $groupId: $currentCount -> $actualCount');
      } else {
        _logger.d('Member count correct for group $groupId: $actualCount');
      }
    } catch (e) {
      _logger.e('Error repairing member count', error: e);
    }
  }

  Future<GroupMembership?> _getMembership(String groupId, String userId) async {
    try {
      final doc =
          await _groupsRef.doc(groupId).collection('members').doc(userId).get();

      if (!doc.exists) return null;
      return GroupMembershipModel.fromFirestore(doc, groupId);
    } catch (e) {
      _logger.e('Error getting membership', error: e);
      return null;
    }
  }

  /// Batch-fetches groups by IDs using Firestore `whereIn` queries.
  ///
  /// Fetches in parallel batches of 10 (Firestore `whereIn` limit).
  /// This reduces N individual network round-trips to ceil(N/10) batch queries,
  /// dramatically improving load time for users with many groups.
  Future<List<LocationGroup>> _batchFetchGroups(List<String> groupIds) async {
    if (groupIds.isEmpty) return [];

    final batchFutures = <Future<List<LocationGroup>>>[];
    for (var i = 0; i < groupIds.length; i += 10) {
      final batchIds = groupIds.sublist(
        i,
        (i + 10 > groupIds.length) ? groupIds.length : i + 10,
      );
      batchFutures.add(
        _groupsRef
            .where(FieldPath.documentId, whereIn: batchIds)
            .where('status', isEqualTo: 'active')
            .get()
            .then((snapshot) => snapshot.docs
                .map((doc) => LocationGroupModel.fromFirestore(doc))
                .toList()),
      );
    }

    final results = await Future.wait(batchFutures);
    return results.expand((list) => list).toList();
  }

  /// Updates last activity timestamp for a group (called when messages are sent).
  Future<void> updateLastActivity(
      String groupId, String? messagePreview) async {
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
    int batchSize = 450, // Safer limit (Firestore max is 500)
    Set<String> skipDocIds = const {},
  }) async {
    final collectionRef = _groupsRef.doc(groupId).collection(subcollection);

    while (true) {
      final snapshot = await collectionRef.limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final docsToDelete =
          snapshot.docs.where((d) => !skipDocIds.contains(d.id)).toList();
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
    int batchSize = 450,
  }) async {
    try {
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
    } catch (e) {
      _logger.e('Error soft-deleting messages', error: e);
      rethrow;
    }
  }
}
