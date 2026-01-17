import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/connection.dart';
import '../domain/entities/connection_request.dart';
import 'models/connection_model.dart';
import 'models/connection_request_model.dart';

/// Result type for connection operations.
sealed class ConnectionResult<T> {
  const ConnectionResult();
}

class ConnectionSuccess<T> extends ConnectionResult<T> {
  final T data;
  const ConnectionSuccess(this.data);
}

class ConnectionFailure<T> extends ConnectionResult<T> {
  final String message;
  final ConnectionErrorType type;
  const ConnectionFailure(this.message, this.type);
}

enum ConnectionErrorType {
  rateLimitExceeded,
  alreadyConnected,
  alreadyPending,
  selfRequest,
  blockedUser,
  requestNotFound,
  unauthorized,
  cooldownActive,
  networkError,
  unknown,
}

/// Service for managing user connections via Firestore.
///
/// Implements:
/// - Mutual consent connection system
/// - Rate limiting for spam prevention
/// - Cooldown periods for rejected requests
/// - Connection blocking
///
/// Firestore Collections:
/// - `connections` - Mutual connections between users
/// - `connection_requests` - Pending/historical requests
/// - `users/{userId}/rate_limits/connection_requests` - Rate limit tracking
/// - `users/{userId}/blocked_users/{blockedId}` - Blocked users list
class ConnectionService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  // Collection references
  late final CollectionReference<Map<String, dynamic>> _connectionsRef;
  late final CollectionReference<Map<String, dynamic>> _requestsRef;

  ConnectionService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger() {
    _connectionsRef = _firestore.collection('connections');
    _requestsRef = _firestore.collection('connection_requests');
  }

  // ==================== CONNECTION REQUESTS ====================

  /// Sends a connection request to another user.
  ///
  /// Validates:
  /// - Not self-request
  /// - Not already connected
  /// - No pending request exists
  /// - Not blocked by recipient
  /// - Rate limits not exceeded
  /// - Cooldown period respected (if previously rejected)
  Future<ConnectionResult<ConnectionRequest>> sendRequest({
    required String senderId,
    required String receiverId,
    String? message,
    String? source,
    String? senderDisplayName,
    String? senderPhotoUrl,
    String? receiverDisplayName,
    String? receiverPhotoUrl,
  }) async {
    try {
      // Validate: Not self-request
      if (senderId == receiverId) {
        return const ConnectionFailure(
          'Cannot send request to yourself',
          ConnectionErrorType.selfRequest,
        );
      }

      // Check if already connected
      final existingConnection = await getConnection(senderId, receiverId);
      if (existingConnection != null) {
        if (existingConnection.status == ConnectionStatus.connected) {
          return const ConnectionFailure(
            'Already connected with this user',
            ConnectionErrorType.alreadyConnected,
          );
        }
        if (existingConnection.status == ConnectionStatus.blocked) {
          return const ConnectionFailure(
            'Cannot send request to this user',
            ConnectionErrorType.blockedUser,
          );
        }
      }

      // Check if blocked
      final isBlocked = await _isUserBlocked(receiverId, senderId);
      if (isBlocked) {
        return const ConnectionFailure(
          'Cannot send request to this user',
          ConnectionErrorType.blockedUser,
        );
      }

      // Check for existing pending request
      final existingRequest = await _getExistingRequest(senderId, receiverId);
      if (existingRequest != null) {
        if (existingRequest.status == ConnectionRequestStatus.pending) {
          return const ConnectionFailure(
            'Request already pending',
            ConnectionErrorType.alreadyPending,
          );
        }

        // Check cooldown for rejected requests
        if (existingRequest.status == ConnectionRequestStatus.rejected &&
            existingRequest.respondedAt != null) {
          final cooldownEnd = existingRequest.respondedAt!.add(
            const Duration(hours: ConnectionRateLimits.rejectionCooldownHours),
          );
          if (DateTime.now().isBefore(cooldownEnd)) {
            return const ConnectionFailure(
              'Please wait before sending another request',
              ConnectionErrorType.cooldownActive,
            );
          }
        }
      }

      // Check rate limits
      final rateLimitResult = await _checkAndUpdateRateLimit(senderId);
      if (rateLimitResult != null) {
        return rateLimitResult;
      }

      // Create request
      final now = DateTime.now();
      final requestId = _requestsRef.doc().id;
      final request = ConnectionRequestModel(
        id: requestId,
        senderId: senderId,
        receiverId: receiverId,
        status: ConnectionRequestStatus.pending,
        sentAt: now,
        expiresAt: now.add(
          const Duration(days: ConnectionRateLimits.requestExpirationDays),
        ),
        message: message,
        source: source,
        senderDisplayName: senderDisplayName,
        senderPhotoUrl: senderPhotoUrl,
        receiverDisplayName: receiverDisplayName,
        receiverPhotoUrl: receiverPhotoUrl,
      );

      await _requestsRef
          .doc(requestId)
          .set(request.toFirestore(useServerTimestamp: true));

      _logger.i('Connection request sent: $senderId -> $receiverId');
      return ConnectionSuccess(request.toEntity());
    } catch (e, stack) {
      _logger.e('Error sending connection request',
          error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to send request: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  /// Accepts a connection request, creating a mutual connection.
  Future<ConnectionResult<Connection>> acceptRequest({
    required String requestId,
    required String currentUserId,
  }) async {
    try {
      return await _firestore.runTransaction((transaction) async {
        // Get request
        final requestDoc = await transaction.get(_requestsRef.doc(requestId));
        if (!requestDoc.exists) {
          return const ConnectionFailure(
            'Request not found',
            ConnectionErrorType.requestNotFound,
          );
        }

        final request = ConnectionRequestModel.fromFirestore(requestDoc);

        // Validate: Current user is the receiver
        if (request.receiverId != currentUserId) {
          return const ConnectionFailure(
            'Not authorized to accept this request',
            ConnectionErrorType.unauthorized,
          );
        }

        // Validate: Request is pending
        if (request.status != ConnectionRequestStatus.pending) {
          return ConnectionFailure(
            'Request is no longer pending (${request.status.name})',
            ConnectionErrorType.requestNotFound,
          );
        }

        // Validate: Not expired
        if (request.isExpired) {
          // Update request status to expired
          transaction.update(_requestsRef.doc(requestId), {
            'status': ConnectionRequestStatus.expired.name,
          });
          return const ConnectionFailure(
            'Request has expired',
            ConnectionErrorType.requestNotFound,
          );
        }

        // Create connection
        final connectionId = Connection.createConnectionId(
          request.senderId,
          request.receiverId,
        );
        final now = DateTime.now();
        final sortedIds = [request.senderId, request.receiverId]..sort();

        final connection = ConnectionModel(
          id: connectionId,
          userId1: sortedIds[0],
          userId2: sortedIds[1],
          status: ConnectionStatus.connected,
          connectedAt: now,
          updatedAt: now,
          initiatedBy: request.senderId,
        );

        // Write connection
        transaction.set(
          _connectionsRef.doc(connectionId),
          connection.toFirestore(),
        );

        // Update request status
        transaction.update(_requestsRef.doc(requestId), {
          'status': ConnectionRequestStatus.accepted.name,
          'respondedAt': Timestamp.fromDate(now),
        });

        _logger.i(
            'Connection accepted: ${request.senderId} <-> ${request.receiverId}');
        return ConnectionSuccess(connection.toEntity());
      });
    } catch (e, stack) {
      _logger.e('Error accepting request', error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to accept request: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  /// Rejects a connection request.
  Future<ConnectionResult<void>> rejectRequest({
    required String requestId,
    required String currentUserId,
  }) async {
    try {
      final requestDoc = await _requestsRef.doc(requestId).get();
      if (!requestDoc.exists) {
        return const ConnectionFailure(
          'Request not found',
          ConnectionErrorType.requestNotFound,
        );
      }

      final request = ConnectionRequestModel.fromFirestore(requestDoc);

      // Validate: Current user is the receiver
      if (request.receiverId != currentUserId) {
        return const ConnectionFailure(
          'Not authorized to reject this request',
          ConnectionErrorType.unauthorized,
        );
      }

      // Update request
      await _requestsRef.doc(requestId).update({
        'status': ConnectionRequestStatus.rejected.name,
        'respondedAt': Timestamp.fromDate(DateTime.now()),
      });

      _logger.i(
          'Connection rejected: ${request.senderId} -> ${request.receiverId}');
      return const ConnectionSuccess(null);
    } catch (e, stack) {
      _logger.e('Error rejecting request', error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to reject request: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  /// Cancels a sent connection request.
  Future<ConnectionResult<void>> cancelRequest({
    required String requestId,
    required String currentUserId,
  }) async {
    try {
      final requestDoc = await _requestsRef.doc(requestId).get();
      if (!requestDoc.exists) {
        return const ConnectionFailure(
          'Request not found',
          ConnectionErrorType.requestNotFound,
        );
      }

      final request = ConnectionRequestModel.fromFirestore(requestDoc);

      // Validate: Current user is the sender
      if (request.senderId != currentUserId) {
        return const ConnectionFailure(
          'Not authorized to cancel this request',
          ConnectionErrorType.unauthorized,
        );
      }

      // Validate: Request is still pending
      if (request.status != ConnectionRequestStatus.pending) {
        return const ConnectionFailure(
          'Request is no longer pending',
          ConnectionErrorType.requestNotFound,
        );
      }

      // Update request
      await _requestsRef.doc(requestId).update({
        'status': ConnectionRequestStatus.cancelled.name,
        'respondedAt': Timestamp.fromDate(DateTime.now()),
      });

      _logger.i(
          'Connection cancelled: ${request.senderId} -> ${request.receiverId}');
      return const ConnectionSuccess(null);
    } catch (e, stack) {
      _logger.e('Error cancelling request', error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to cancel request: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  // ==================== CONNECTIONS ====================

  /// Gets an existing connection between two users.
  Future<Connection?> getConnection(String userId1, String userId2) async {
    try {
      final connectionId = Connection.createConnectionId(userId1, userId2);
      final doc = await _connectionsRef.doc(connectionId).get();

      if (!doc.exists) return null;
      return ConnectionModel.fromFirestore(doc).toEntity();
    } catch (e, stack) {
      _logger.e('Error getting connection', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Removes/disconnects from a user.
  Future<ConnectionResult<void>> removeConnection({
    required String connectionId,
    required String currentUserId,
  }) async {
    try {
      final doc = await _connectionsRef.doc(connectionId).get();
      if (!doc.exists) {
        return const ConnectionFailure(
          'Connection not found',
          ConnectionErrorType.requestNotFound,
        );
      }

      final connection = ConnectionModel.fromFirestore(doc);

      // Validate user is part of connection
      if (!connection.hasUser(currentUserId)) {
        return const ConnectionFailure(
          'Not authorized',
          ConnectionErrorType.unauthorized,
        );
      }

      // Update status to disconnected
      await _connectionsRef.doc(connectionId).update({
        'status': ConnectionStatus.disconnected.name,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });

      _logger.i('Connection removed: $connectionId');
      return const ConnectionSuccess(null);
    } catch (e, stack) {
      _logger.e('Error removing connection', error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to remove connection: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  /// Blocks a user.
  Future<ConnectionResult<void>> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      final batch = _firestore.batch();

      // Add to blocked users
      batch.set(
        _firestore
            .collection('users')
            .doc(blockerId)
            .collection('blocked_users')
            .doc(blockedId),
        {
          'blockedAt': Timestamp.fromDate(DateTime.now()),
        },
      );

      // Update connection if exists
      final connectionId = Connection.createConnectionId(blockerId, blockedId);
      final connectionDoc = await _connectionsRef.doc(connectionId).get();

      if (connectionDoc.exists) {
        batch.update(_connectionsRef.doc(connectionId), {
          'status': ConnectionStatus.blocked.name,
          'blockedBy': blockerId,
          'updatedAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      // Cancel any pending requests
      final pendingRequests = await _requestsRef
          .where('senderId', isEqualTo: blockedId)
          .where('receiverId', isEqualTo: blockerId)
          .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
          .get();

      for (final doc in pendingRequests.docs) {
        batch.update(doc.reference, {
          'status': ConnectionRequestStatus.rejected.name,
          'respondedAt': Timestamp.fromDate(DateTime.now()),
        });
      }

      await batch.commit();

      _logger.i('User blocked: $blockerId blocked $blockedId');
      return const ConnectionSuccess(null);
    } catch (e, stack) {
      _logger.e('Error blocking user', error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to block user: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  /// Unblocks a user.
  Future<ConnectionResult<void>> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    try {
      // Remove from blocked users
      await _firestore
          .collection('users')
          .doc(blockerId)
          .collection('blocked_users')
          .doc(blockedId)
          .delete();

      // Update connection status if exists
      final connectionId = Connection.createConnectionId(blockerId, blockedId);
      final connectionDoc = await _connectionsRef.doc(connectionId).get();

      if (connectionDoc.exists) {
        final connection = ConnectionModel.fromFirestore(connectionDoc);
        if (connection.blockedBy == blockerId) {
          await _connectionsRef.doc(connectionId).update({
            'status': ConnectionStatus.disconnected.name,
            'blockedBy': null,
            'updatedAt': Timestamp.fromDate(DateTime.now()),
          });
        }
      }

      _logger.i('User unblocked: $blockerId unblocked $blockedId');
      return const ConnectionSuccess(null);
    } catch (e, stack) {
      _logger.e('Error unblocking user', error: e, stackTrace: stack);
      return ConnectionFailure(
        'Failed to unblock user: ${e.toString()}',
        ConnectionErrorType.networkError,
      );
    }
  }

  // ==================== STREAMS ====================

  /// Stream of received connection requests (inbox).
  Stream<List<ConnectionRequest>> getReceivedRequestsStream(String userId) {
    return _requestsRef
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConnectionRequestModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Stream of sent connection requests.
  Stream<List<ConnectionRequest>> getSentRequestsStream(String userId) {
    return _requestsRef
        .where('senderId', isEqualTo: userId)
        .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
        .orderBy('sentAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConnectionRequestModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Stream of user's connections.
  Stream<List<Connection>> getConnectionsStream(String userId) {
    return _connectionsRef
        .where('users', arrayContains: userId)
        .where('status', isEqualTo: ConnectionStatus.connected.name)
        .orderBy('connectedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConnectionModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Gets the count of pending received requests.
  Stream<int> getPendingRequestCountStream(String userId) {
    return _requestsRef
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ==================== QUERIES ====================

  /// Gets connection status between current user and another user.
  Future<UserConnectionState> getConnectionState({
    required String currentUserId,
    required String otherUserId,
  }) async {
    try {
      // Check for existing connection
      final connection = await getConnection(currentUserId, otherUserId);
      if (connection != null) {
        return switch (connection.status) {
          ConnectionStatus.connected => UserConnectionState.connected,
          ConnectionStatus.blocked => UserConnectionState.blocked,
          ConnectionStatus.disconnected => UserConnectionState.notConnected,
        };
      }

      // Check for pending request from current user
      final sentRequest = await _requestsRef
          .where('senderId', isEqualTo: currentUserId)
          .where('receiverId', isEqualTo: otherUserId)
          .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
          .limit(1)
          .get();

      if (sentRequest.docs.isNotEmpty) {
        return UserConnectionState.requestSent;
      }

      // Check for pending request from other user
      final receivedRequest = await _requestsRef
          .where('senderId', isEqualTo: otherUserId)
          .where('receiverId', isEqualTo: currentUserId)
          .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
          .limit(1)
          .get();

      if (receivedRequest.docs.isNotEmpty) {
        return UserConnectionState.requestReceived;
      }

      return UserConnectionState.notConnected;
    } catch (e, stack) {
      _logger.e('Error getting connection state', error: e, stackTrace: stack);
      return UserConnectionState.notConnected;
    }
  }

  /// Gets a pending request between two users (if any).
  Future<ConnectionRequest?> getPendingRequest({
    required String userId1,
    required String userId2,
  }) async {
    try {
      // Check both directions
      final query1 = await _requestsRef
          .where('senderId', isEqualTo: userId1)
          .where('receiverId', isEqualTo: userId2)
          .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
          .limit(1)
          .get();

      if (query1.docs.isNotEmpty) {
        return ConnectionRequestModel.fromFirestore(query1.docs.first)
            .toEntity();
      }

      final query2 = await _requestsRef
          .where('senderId', isEqualTo: userId2)
          .where('receiverId', isEqualTo: userId1)
          .where('status', isEqualTo: ConnectionRequestStatus.pending.name)
          .limit(1)
          .get();

      if (query2.docs.isNotEmpty) {
        return ConnectionRequestModel.fromFirestore(query2.docs.first)
            .toEntity();
      }

      return null;
    } catch (e, stack) {
      _logger.e('Error getting pending request', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Gets list of blocked user IDs.
  Future<List<String>> getBlockedUserIds(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('blocked_users')
          .get();

      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e, stack) {
      _logger.e('Error getting blocked users', error: e, stackTrace: stack);
      return [];
    }
  }

  // ==================== PRIVATE HELPERS ====================

  /// Checks if a user is blocked by another user.
  Future<bool> _isUserBlocked(String blockerId, String blockedId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(blockerId)
          .collection('blocked_users')
          .doc(blockedId)
          .get();

      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Gets existing request between two users (any direction, most recent).
  Future<ConnectionRequest?> _getExistingRequest(
    String userId1,
    String userId2,
  ) async {
    try {
      // Query both directions
      final query1 = await _requestsRef
          .where('senderId', isEqualTo: userId1)
          .where('receiverId', isEqualTo: userId2)
          .orderBy('sentAt', descending: true)
          .limit(1)
          .get();

      final query2 = await _requestsRef
          .where('senderId', isEqualTo: userId2)
          .where('receiverId', isEqualTo: userId1)
          .orderBy('sentAt', descending: true)
          .limit(1)
          .get();

      ConnectionRequest? request1;
      ConnectionRequest? request2;

      if (query1.docs.isNotEmpty) {
        request1 =
            ConnectionRequestModel.fromFirestore(query1.docs.first).toEntity();
      }
      if (query2.docs.isNotEmpty) {
        request2 =
            ConnectionRequestModel.fromFirestore(query2.docs.first).toEntity();
      }

      // Return most recent
      if (request1 == null) return request2;
      if (request2 == null) return request1;
      return request1.sentAt.isAfter(request2.sentAt) ? request1 : request2;
    } catch (e) {
      return null;
    }
  }

  /// Checks rate limits and updates if allowed.
  Future<ConnectionFailure<ConnectionRequest>?> _checkAndUpdateRateLimit(
    String userId,
  ) async {
    try {
      final rateLimitDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('rate_limits')
          .doc('connection_requests')
          .get();

      var rateLimit = RequestRateLimitModel.fromFirestore(rateLimitDoc);

      // Reset counters if expired
      final now = DateTime.now();
      if (now.isAfter(rateLimit.hourlyResetAt)) {
        rateLimit = RequestRateLimitModel(
          hourlyCount: 0,
          hourlyResetAt: now.add(const Duration(hours: 1)),
          dailyCount: rateLimit.dailyCount,
          dailyResetAt: rateLimit.dailyResetAt,
          lastRequestAt: rateLimit.lastRequestAt,
        );
      }
      if (now.isAfter(rateLimit.dailyResetAt)) {
        rateLimit = RequestRateLimitModel(
          hourlyCount: rateLimit.hourlyCount,
          hourlyResetAt: rateLimit.hourlyResetAt,
          dailyCount: 0,
          dailyResetAt: DateTime(now.year, now.month, now.day + 1),
          lastRequestAt: rateLimit.lastRequestAt,
        );
      }

      // Check limits
      if (rateLimit.isHourlyLimitExceeded) {
        final minutesLeft =
            rateLimit.hourlyResetAt.difference(now).inMinutes + 1;
        return ConnectionFailure(
          'Hourly limit reached. Try again in $minutesLeft minutes.',
          ConnectionErrorType.rateLimitExceeded,
        );
      }

      if (rateLimit.isDailyLimitExceeded) {
        return const ConnectionFailure(
          'Daily limit reached. Try again tomorrow.',
          ConnectionErrorType.rateLimitExceeded,
        );
      }

      // Update rate limit
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('rate_limits')
          .doc('connection_requests')
          .set(rateLimit.increment().toFirestore());

      return null;
    } catch (e) {
      // Don't block on rate limit errors, log and continue
      _logger.w('Rate limit check failed', error: e);
      return null;
    }
  }

  // ==================== USER PROFILE FETCHING ====================

  /// Fetches user profile by ID.
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      // Privacy: fetch public profile data from `profiles` instead of `users`.
      final doc = await _firestore.collection('profiles').doc(userId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      return {
        'id': doc.id,
        'displayName': data['name'] ?? 'User',
        'avatarUrl': data['photoUrl'],
        'bio': data['bio'],
        'isOnline': data['isOnline'] ?? false,
        'lastSeen': data['lastSeen'],
      };
    } catch (e, stack) {
      _logger.e('Error fetching user profile', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Fetches multiple user profiles by IDs.
  Future<Map<String, Map<String, dynamic>>> getUserProfiles(
      List<String> userIds) async {
    if (userIds.isEmpty) return {};

    try {
      final results = <String, Map<String, dynamic>>{};

      // Firestore limits 'in' queries to 30 items
      final chunks = <List<String>>[];
      for (var i = 0; i < userIds.length; i += 30) {
        chunks.add(userIds.sublist(
          i,
          i + 30 > userIds.length ? userIds.length : i + 30,
        ));
      }

      for (final chunk in chunks) {
        final snapshot = await _firestore
            .collection('profiles')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          results[doc.id] = {
            'id': doc.id,
            'displayName': data['name'] ?? 'User',
            'avatarUrl': data['photoUrl'],
            'bio': data['bio'],
            'isOnline': data['isOnline'] ?? false,
            'lastSeen': data['lastSeen'],
          };
        }
      }

      return results;
    } catch (e, stack) {
      _logger.e('Error fetching user profiles', error: e, stackTrace: stack);
      return {};
    }
  }

  /// Stream of user's connections with user profile data.
  Stream<List<Map<String, dynamic>>> getConnectionsWithProfilesStream(
      String userId) {
    return getConnectionsStream(userId).asyncMap((connections) async {
      if (connections.isEmpty) return [];

      // Get other user IDs
      final otherUserIds =
          connections.map((c) => c.getOtherUserId(userId)).toList();

      // Fetch profiles
      final profiles = await getUserProfiles(otherUserIds);

      // Combine connection with profile data
      return connections.map((connection) {
        final otherUserId = connection.getOtherUserId(userId);
        final profile = profiles[otherUserId];

        return {
          'connection': connection,
          'userId': otherUserId,
          'displayName': profile?['displayName'] ?? 'User',
          'avatarUrl': profile?['avatarUrl'],
          'bio': profile?['bio'],
          'isOnline': profile?['isOnline'] ?? false,
          'lastSeen': profile?['lastSeen'],
        };
      }).toList();
    });
  }
}

/// Represents the connection state between two users.
enum UserConnectionState {
  /// No connection or request exists.
  notConnected,

  /// Current user sent a request (pending).
  requestSent,

  /// Current user received a request (pending).
  requestReceived,

  /// Users are connected.
  connected,

  /// One user blocked the other.
  blocked,
}
