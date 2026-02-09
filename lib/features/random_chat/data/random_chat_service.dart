import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/random_chat_connection.dart';
import '../domain/entities/random_chat_request.dart';
import '../domain/entities/random_chat_user.dart';
import 'models/random_chat_connection_model.dart';
import 'models/random_chat_request_model.dart';

/// Result type for random chat operations.
sealed class RandomChatResult<T> {
  const RandomChatResult();
}

class RandomChatSuccess<T> extends RandomChatResult<T> {
  final T data;
  const RandomChatSuccess(this.data);
}

class RandomChatFailure<T> extends RandomChatResult<T> {
  final String message;
  final RandomChatErrorType type;
  const RandomChatFailure(this.message, this.type);
}

enum RandomChatErrorType {
  receiverLimitReached,
  alreadyRequested,
  alreadyConnected,
  requestExpired,
  dayChanged,
  notFound,
  networkError,
  unknown,
}

/// Service for managing the daily Random Chat feature.
///
/// Firestore Collections:
/// ```
/// random_chat_daily/{dateKey}/suggestions/{userId}
///   - suggestedUserIds: [list of suggested user IDs]
///   - generatedAt: timestamp
///
/// random_chat_daily/{dateKey}/requests/{requestId}
///   - senderId, receiverId, status, timestamps
///
/// random_chat_daily/{dateKey}/connections/{connectionId}
///   - user1Id, user2Id, participantIds, timestamps
///
/// random_chat_daily/{dateKey}/user_stats/{userId}
///   - receivedRequestCount: int
///   - sentRequestCount: int
///   - hasActiveConnection: bool
/// ```
class RandomChatService {
  final FirebaseFirestore _firestore;
  final Logger _logger;
  final Random _random;

  static const int maxDailyUsers = 10;
  static const int maxDailyReceivedRequests = 10;

  RandomChatService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger(),
        _random = Random();

  // ---------------------------------------------------------------------------
  // Date helpers
  // ---------------------------------------------------------------------------

  /// Returns today's date key in 'yyyy-MM-dd' format (local time).
  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Checks if a date key matches today.
  bool _isToday(String dateKey) => dateKey == _todayKey;

  /// Reference to today's daily collection.
  DocumentReference _dailyDoc(String dateKey) =>
      _firestore.collection('random_chat_daily').doc(dateKey);

  CollectionReference<Map<String, dynamic>> _suggestionsCol(String dateKey) =>
      _dailyDoc(dateKey).collection('suggestions');

  CollectionReference<Map<String, dynamic>> _requestsCol(String dateKey) =>
      _dailyDoc(dateKey).collection('requests');

  CollectionReference<Map<String, dynamic>> _connectionsCol(String dateKey) =>
      _dailyDoc(dateKey).collection('connections');

  CollectionReference<Map<String, dynamic>> _userStatsCol(String dateKey) =>
      _dailyDoc(dateKey).collection('user_stats');

  // ---------------------------------------------------------------------------
  // Daily user discovery
  // ---------------------------------------------------------------------------

  /// Fetches or generates the daily list of up to 10 random users for [currentUserId].
  ///
  /// Uses gender priority logic: if user has gender set, prioritize opposite gender.
  /// Results are cached in Firestore so reopening the page shows the same list.
  Future<List<RandomChatUser>> getDailySuggestions({
    required String currentUserId,
    String? currentUserGender,
  }) async {
    final dateKey = _todayKey;

    try {
      // Check if suggestions already generated for today
      final existingDoc = await _suggestionsCol(dateKey).doc(currentUserId).get();

      if (existingDoc.exists) {
        final data = existingDoc.data()!;
        final suggestedIds = List<String>.from(data['suggestedUserIds'] ?? []);

        if (suggestedIds.isNotEmpty) {
          _logger.d('Returning ${suggestedIds.length} cached suggestions for $dateKey');
          // Fetch user details for suggested IDs
          return _fetchUserDetails(suggestedIds, dateKey);
        }
        _logger.d('Cached suggestions exist but are empty — regenerating');
      }

      // Generate new suggestions
      return _generateDailySuggestions(
        currentUserId: currentUserId,
        currentUserGender: currentUserGender,
        dateKey: dateKey,
      );
    } catch (e, stack) {
      _logger.e('Error fetching daily suggestions', error: e, stackTrace: stack);
      // Rethrow so the BLoC can show a meaningful error to the user
      rethrow;
    }
  }

  /// Generates a fresh list of random users and stores them.
  Future<List<RandomChatUser>> _generateDailySuggestions({
    required String currentUserId,
    String? currentUserGender,
    required String dateKey,
  }) async {
    try {
      // Get all profiles - we'll filter by visibility in Dart code
      // This is necessary because isVisible may not exist on all documents,
      // and Firestore queries don't support default values like Dart does
      final usersSnapshot = await _firestore
          .collection('profiles')
          .get();

      _logger.d('Profiles query returned ${usersSnapshot.docs.length} documents');

      final allUsers = usersSnapshot.docs
          .where((doc) {
            if (doc.id == currentUserId) return false;
            
            // Apply isVisible filter with default value of true
            // If the field doesn't exist, treat as visible
            final data = doc.data();
            final isVisible = data['isVisible'] as bool? ?? true;
            return isVisible;
          })
          .toList();

      _logger.d('After filtering self & invisible: ${allUsers.length} eligible profiles');

      if (allUsers.isEmpty) {
        _logger.w('No visible profiles found (total docs: ${usersSnapshot.docs.length}, currentUserId: $currentUserId)');
        return [];
      }

      // Get users who already have 10 received requests today
      final saturatedUserIds = await _getSaturatedUserIds(dateKey);

      // Get users who already have an active connection today
      final connectedUserIds = await _getConnectedUserIds(dateKey);

      // Filter out ineligible users
      final excludeIds = {...saturatedUserIds, ...connectedUserIds, currentUserId};

      final eligibleUsers = allUsers
          .where((doc) => !excludeIds.contains(doc.id))
          .toList();

      _logger.d('Saturated: ${saturatedUserIds.length}, Connected: ${connectedUserIds.length}, '
          'Eligible after exclusions: ${eligibleUsers.length}');

      if (eligibleUsers.isEmpty) {
        _logger.w('All users filtered out (saturated=${saturatedUserIds.length}, connected=${connectedUserIds.length})');
        // Store empty suggestions
        await _suggestionsCol(dateKey).doc(currentUserId).set({
          'suggestedUserIds': <String>[],
          'generatedAt': FieldValue.serverTimestamp(),
        });
        return [];
      }

      // Apply gender priority logic
      List<DocumentSnapshot> selectedDocs;

      if (currentUserGender != null && currentUserGender.isNotEmpty) {
        final oppositeGender = _getOppositeGender(currentUserGender);

        final oppositeGenderUsers = eligibleUsers
            .where((doc) {
              final data = doc.data();
              final gender = data['gender'] as String?;
              return gender != null &&
                  gender.toLowerCase() == oppositeGender.toLowerCase();
            })
            .toList();

        final otherUsers = eligibleUsers
            .where((doc) {
              final data = doc.data();
              final gender = data['gender'] as String?;
              return gender == null ||
                  gender.toLowerCase() != oppositeGender.toLowerCase();
            })
            .toList();

        // Shuffle both lists
        oppositeGenderUsers.shuffle(_random);
        otherUsers.shuffle(_random);

        // Take opposite gender first, fill remaining with others
        selectedDocs = [
          ...oppositeGenderUsers.take(maxDailyUsers),
        ];

        if (selectedDocs.length < maxDailyUsers) {
          final remaining = maxDailyUsers - selectedDocs.length;
          selectedDocs.addAll(otherUsers.take(remaining));
        }
      } else {
        // No gender set - random selection
        eligibleUsers.shuffle(_random);
        selectedDocs = eligibleUsers.take(maxDailyUsers).toList();
      }

      final suggestedIds = selectedDocs.map((doc) => doc.id).toList();

      _logger.d('Generated ${suggestedIds.length} suggestions for $dateKey: $suggestedIds');

      // Store suggestions in Firestore
      await _suggestionsCol(dateKey).doc(currentUserId).set({
        'suggestedUserIds': suggestedIds,
        'generatedAt': FieldValue.serverTimestamp(),
      });

      // Convert to RandomChatUser entities
      return _docsToRandomChatUsers(selectedDocs, dateKey);
    } catch (e, stack) {
      _logger.e('Error generating daily suggestions', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Fetches user details for a list of user IDs from the profiles collection.
  Future<List<RandomChatUser>> _fetchUserDetails(
    List<String> userIds,
    String dateKey,
  ) async {
    if (userIds.isEmpty) return [];

    try {
      // Firestore 'in' queries support max 30 items
      final List<RandomChatUser> result = [];

      for (var i = 0; i < userIds.length; i += 30) {
        final batch = userIds.sublist(
          i,
          i + 30 > userIds.length ? userIds.length : i + 30,
        );

        final snapshot = await _firestore
            .collection('profiles')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data();

          result.add(RandomChatUser(
            userId: doc.id,
            displayName:
                data['displayName'] as String? ?? data['name'] as String? ?? 'Unknown',
            photoUrl: data['photoUrl'] as String?,
            gender: data['gender'] as String?,
            mood: data['mood'] as String?,
            bio: data['bio'] as String?,
            receivedRequestCount: 0, // updated below in batch
          ));
        }
      }

      // Batch-read all stats in parallel instead of N sequential reads
      final statsFutures = result.map(
        (u) => _userStatsCol(dateKey).doc(u.userId).get(),
      );
      final statsDocs = await Future.wait(statsFutures);

      final statsMap = <String, int>{};
      for (final statsDoc in statsDocs) {
        if (statsDoc.exists) {
          statsMap[statsDoc.id] =
              (statsDoc.data()?['receivedRequestCount'] as int?) ?? 0;
        }
      }

      // Update users with actual stats
      final updatedResult = result.map((u) {
        final count = statsMap[u.userId] ?? 0;
        return u.copyWith(receivedRequestCount: count);
      }).toList();

      // Preserve original order
      final orderedResult = <RandomChatUser>[];
      for (final id in userIds) {
        final user = updatedResult.where((u) => u.userId == id).firstOrNull;
        if (user != null) orderedResult.add(user);
      }

      return orderedResult;
    } catch (e, stack) {
      _logger.e('Error fetching user details', error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<RandomChatUser>> _docsToRandomChatUsers(
    List<DocumentSnapshot> docs,
    String dateKey,
  ) async {
    // Batch-read all stats in parallel instead of N sequential reads
    final statsFutures = docs.map(
      (doc) => _userStatsCol(dateKey).doc(doc.id).get(),
    );
    final statsDocs = await Future.wait(statsFutures);

    final statsMap = <String, int>{};
    for (final statsDoc in statsDocs) {
      if (statsDoc.exists) {
        statsMap[statsDoc.id] =
            (statsDoc.data()?['receivedRequestCount'] as int?) ?? 0;
      }
    }

    final result = <RandomChatUser>[];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final receivedCount = statsMap[doc.id] ?? 0;

      result.add(RandomChatUser(
        userId: doc.id,
        displayName:
            data['displayName'] as String? ?? data['name'] as String? ?? 'Unknown',
        photoUrl: data['photoUrl'] as String?,
        gender: data['gender'] as String?,
        mood: data['mood'] as String?,
        bio: data['bio'] as String?,
        receivedRequestCount: receivedCount,
      ));
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Send / Manage requests
  // ---------------------------------------------------------------------------

  /// Sends a chat request from [senderId] to [receiverId].
  ///
  /// Atomically increments receiver's received request count and checks limits.
  Future<RandomChatResult<RandomChatRequest>> sendRequest({
    required String senderId,
    required String senderDisplayName,
    String? senderPhotoUrl,
    required String receiverId,
    required String receiverDisplayName,
    String? receiverPhotoUrl,
  }) async {
    final dateKey = _todayKey;

    try {
      // Use a transaction with deterministic doc IDs for atomic checks.
      // Firestore transactions only guarantee consistency for docs read
      // via transaction.get(), NOT for collection queries.
      final result = await _firestore.runTransaction<RandomChatResult<RandomChatRequest>>(
        (transaction) async {
          // 1. Check if already sent a request to this user today
          //    Use deterministic doc ID so we can read it transactionally.
          final requestDocId = '${senderId}_$receiverId';
          final requestRef = _requestsCol(dateKey).doc(requestDocId);
          final existingDoc = await transaction.get(requestRef);

          if (existingDoc.exists) {
            return const RandomChatFailure(
              'You have already sent a request to this user today',
              RandomChatErrorType.alreadyRequested,
            );
          }

          // 2. Read BOTH users' daily stats transactionally
          final receiverStatsRef = _userStatsCol(dateKey).doc(receiverId);
          final senderStatsRef = _userStatsCol(dateKey).doc(senderId);
          final receiverStatsDoc = await transaction.get(receiverStatsRef);
          final senderStatsDoc = await transaction.get(senderStatsRef);

          final receiverStats = receiverStatsDoc.data() ?? {};
          final senderStats = senderStatsDoc.data() ?? {};

          // 3. Check receiver's daily request limit
          final currentCount =
              (receiverStats['receivedRequestCount'] as int?) ?? 0;

          if (currentCount >= maxDailyReceivedRequests) {
            return const RandomChatFailure(
              'This user has reached their daily request limit',
              RandomChatErrorType.receiverLimitReached,
            );
          }

          // 4. Check if either user already has an active connection today
          //    Uses the transactionally-read user_stats instead of querying
          //    the connections collection (which would NOT be transactional).
          if (senderStats['hasActiveConnection'] == true) {
            return const RandomChatFailure(
              'You already have an active Random Chat connection today',
              RandomChatErrorType.alreadyConnected,
            );
          }

          if (receiverStats['hasActiveConnection'] == true) {
            return const RandomChatFailure(
              'This user already has an active Random Chat connection today',
              RandomChatErrorType.alreadyConnected,
            );
          }

          // 5. Create the request (deterministic ID prevents duplicates)
          final request = RandomChatRequestModel(
            id: requestRef.id,
            senderId: senderId,
            receiverId: receiverId,
            senderDisplayName: senderDisplayName,
            senderPhotoUrl: senderPhotoUrl,
            receiverDisplayName: receiverDisplayName,
            receiverPhotoUrl: receiverPhotoUrl,
            status: RandomChatRequestStatus.pending,
            dateKey: dateKey,
            createdAt: DateTime.now(),
          );

          transaction.set(requestRef, request.toFirestore(useServerTimestamp: true));

          // 6. Increment receiver's received count (atomic)
          transaction.set(
            receiverStatsRef,
            {
              'receivedRequestCount': FieldValue.increment(1),
              'lastUpdated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          // 7. Increment sender's sent count
          transaction.set(
            senderStatsRef,
            {
              'sentRequestCount': FieldValue.increment(1),
              'lastUpdated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          return RandomChatSuccess(request.toEntity());
        },
      );

      return result;
    } catch (e, stack) {
      _logger.e('Error sending random chat request', error: e, stackTrace: stack);
      return RandomChatFailure(
        'Failed to send request: ${e.toString()}',
        RandomChatErrorType.networkError,
      );
    }
  }

  /// Accepts a pending chat request.
  ///
  /// Creates a connection between both users.
  Future<RandomChatResult<RandomChatConnection>> acceptRequest({
    required String requestId,
    required String currentUserId,
  }) async {
    final dateKey = _todayKey;

    try {
      final result = await _firestore.runTransaction<RandomChatResult<RandomChatConnection>>(
        (transaction) async {
          // 1. Get the request
          final requestRef = _requestsCol(dateKey).doc(requestId);
          final requestDoc = await transaction.get(requestRef);

          if (!requestDoc.exists) {
            return const RandomChatFailure(
              'Request not found',
              RandomChatErrorType.notFound,
            );
          }

          final request = RandomChatRequestModel.fromFirestore(requestDoc);

          // 2. Check it belongs to current user and is still pending
          if (request.receiverId != currentUserId) {
            return const RandomChatFailure(
              'Unauthorized',
              RandomChatErrorType.unknown,
            );
          }

          if (request.status != RandomChatRequestStatus.pending) {
            return const RandomChatFailure(
              'Request is no longer pending',
              RandomChatErrorType.requestExpired,
            );
          }

          // 3. Verify date hasn't changed (request from today)
          if (!_isToday(request.dateKey)) {
            // Mark as expired
            transaction.update(requestRef, {'status': 'expired'});
            return const RandomChatFailure(
              'This request has expired (day changed)',
              RandomChatErrorType.dayChanged,
            );
          }

          // 4. Check neither user already has active connection
          //    Read user_stats transactionally (not collection queries) for
          //    consistency within the transaction.
          final senderStatsRef = _userStatsCol(dateKey).doc(request.senderId);
          final receiverStatsRef = _userStatsCol(dateKey).doc(request.receiverId);
          final senderStatsDoc = await transaction.get(senderStatsRef);
          final receiverStatsDoc = await transaction.get(receiverStatsRef);

          if (senderStatsDoc.data()?['hasActiveConnection'] == true) {
            return const RandomChatFailure(
              'The sender already has an active connection',
              RandomChatErrorType.alreadyConnected,
            );
          }

          if (receiverStatsDoc.data()?['hasActiveConnection'] == true) {
            return const RandomChatFailure(
              'You already have an active connection today',
              RandomChatErrorType.alreadyConnected,
            );
          }

          // 5. Accept request
          transaction.update(requestRef, {
            'status': 'accepted',
            'respondedAt': FieldValue.serverTimestamp(),
          });

          // 6. Create connection
          final connRef = _connectionsCol(dateKey).doc();
          final connection = RandomChatConnectionModel(
            id: connRef.id,
            user1Id: request.senderId,
            user2Id: request.receiverId,
            user1DisplayName: request.senderDisplayName,
            user1PhotoUrl: request.senderPhotoUrl,
            user2DisplayName: request.receiverDisplayName,
            user2PhotoUrl: request.receiverPhotoUrl,
            dateKey: dateKey,
            createdAt: DateTime.now(),
          );

          transaction.set(
              connRef, connection.toFirestore(useServerTimestamp: true));

          // 7. Mark both users as having an active connection
          transaction.set(
            senderStatsRef,
            {'hasActiveConnection': true, 'lastUpdated': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
          transaction.set(
            receiverStatsRef,
            {'hasActiveConnection': true, 'lastUpdated': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );

          return RandomChatSuccess(connection.toEntity());
        },
      );

      // Best-effort: expire all other pending requests involving the
      // CURRENT user (receiver). The sender's other requests are handled
      // by the onRandomChatConnectionCreated Cloud Function, since the
      // client only has Firestore permission to expire requests where
      // it is sender or receiver. Fire-and-forget.
      if (result is RandomChatSuccess<RandomChatConnection>) {
        _expireOtherPendingRequests(
          dateKey: dateKey,
          currentUserId: currentUserId,
          excludeRequestId: requestId,
        );
      }

      return result;
    } catch (e, stack) {
      _logger.e('Error accepting random chat request', error: e, stackTrace: stack);
      return RandomChatFailure(
        'Failed to accept request: ${e.toString()}',
        RandomChatErrorType.networkError,
      );
    }
  }

  /// Rejects a pending chat request.
  ///
  /// Uses a transaction to prevent race conditions with concurrent accept/reject.
  Future<RandomChatResult<void>> rejectRequest({
    required String requestId,
    required String currentUserId,
  }) async {
    final dateKey = _todayKey;

    try {
      final result = await _firestore.runTransaction<RandomChatResult<void>>(
        (transaction) async {
          final requestRef = _requestsCol(dateKey).doc(requestId);
          final requestDoc = await transaction.get(requestRef);

          if (!requestDoc.exists) {
            return const RandomChatFailure(
                'Request not found', RandomChatErrorType.notFound);
          }

          final request = RandomChatRequestModel.fromFirestore(requestDoc);

          if (request.receiverId != currentUserId) {
            return const RandomChatFailure(
                'Unauthorized', RandomChatErrorType.unknown);
          }

          if (request.status != RandomChatRequestStatus.pending) {
            return const RandomChatFailure(
              'Request is no longer pending',
              RandomChatErrorType.requestExpired,
            );
          }

          transaction.update(requestRef, {
            'status': 'rejected',
            'respondedAt': FieldValue.serverTimestamp(),
          });

          return const RandomChatSuccess(null);
        },
      );

      return result;
    } catch (e, stack) {
      _logger.e('Error rejecting random chat request',
          error: e, stackTrace: stack);
      return RandomChatFailure(
        'Failed to reject request: ${e.toString()}',
        RandomChatErrorType.networkError,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Streams for real-time updates
  // ---------------------------------------------------------------------------

  /// Stream of incoming requests for [userId] for today.
  Stream<List<RandomChatRequest>> watchIncomingRequests(String userId) {
    final dateKey = _todayKey;

    return _requestsCol(dateKey)
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RandomChatRequestModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Stream of sent requests for [userId] for today.
  Stream<List<RandomChatRequest>> watchSentRequests(String userId) {
    final dateKey = _todayKey;

    return _requestsCol(dateKey)
        .where('senderId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RandomChatRequestModel.fromFirestore(doc).toEntity())
            .toList());
  }

  /// Stream of active connection for [userId] for today.
  Stream<RandomChatConnection?> watchActiveConnection(String userId) {
    final dateKey = _todayKey;

    return _connectionsCol(dateKey)
        .where('participantIds', arrayContains: userId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return RandomChatConnectionModel.fromFirestore(snapshot.docs.first).toEntity();
    });
  }

  // ---------------------------------------------------------------------------
  // Fetch operations (non-stream)
  // ---------------------------------------------------------------------------

  /// Fetches all incoming requests (any status) for the current user today.
  Future<List<RandomChatRequest>> getIncomingRequests(String userId) async {
    final dateKey = _todayKey;
    try {
      final snapshot = await _requestsCol(dateKey)
          .where('receiverId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => RandomChatRequestModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e, stack) {
      _logger.e('Error fetching incoming requests', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Gets active connection for user today (if any).
  Future<RandomChatConnection?> getActiveConnection(String userId) async {
    final dateKey = _todayKey;
    try {
      final snapshot = await _connectionsCol(dateKey)
          .where('participantIds', arrayContains: userId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return RandomChatConnectionModel.fromFirestore(snapshot.docs.first).toEntity();
    } catch (e, stack) {
      _logger.e('Error fetching active connection', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Fetches sent requests for the current user today.
  Future<List<RandomChatRequest>> getSentRequests(String userId) async {
    final dateKey = _todayKey;
    try {
      final snapshot = await _requestsCol(dateKey)
          .where('senderId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => RandomChatRequestModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e, stack) {
      _logger.e('Error fetching sent requests', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Gets the user's daily stats.
  Future<Map<String, dynamic>> getUserDailyStats(String userId) async {
    final dateKey = _todayKey;
    try {
      final doc = await _userStatsCol(dateKey).doc(userId).get();
      return doc.data() ?? {};
    } catch (e) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Gets IDs of users who have received 10+ requests today.
  Future<Set<String>> _getSaturatedUserIds(String dateKey) async {
    try {
      final snapshot = await _userStatsCol(dateKey)
          .where('receivedRequestCount', isGreaterThanOrEqualTo: maxDailyReceivedRequests)
          .get();

      return snapshot.docs.map((doc) => doc.id).toSet();
    } catch (e) {
      _logger.w('Error fetching saturated user IDs', error: e);
      return {};
    }
  }

  /// Gets IDs of users who have an active connection today.
  Future<Set<String>> _getConnectedUserIds(String dateKey) async {
    try {
      final snapshot = await _userStatsCol(dateKey)
          .where('hasActiveConnection', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) => doc.id).toSet();
    } catch (e) {
      _logger.w('Error fetching connected user IDs', error: e);
      return {};
    }
  }

  /// Returns the opposite gender string.
  String _getOppositeGender(String gender) {
    switch (gender.toLowerCase()) {
      case 'male':
        return 'female';
      case 'female':
        return 'male';
      default:
        return ''; // non-binary or other - no priority
    }
  }

  /// Best-effort cleanup: expires all other pending requests involving
  /// [currentUserId] (both sent and received). Only processes requests
  /// where the current user is sender or receiver, matching Firestore
  /// security rules. The other connected user's requests are handled
  /// server-side by the onRandomChatConnectionCreated Cloud Function.
  /// Fire-and-forget so it doesn't block the accept response.
  void _expireOtherPendingRequests({
    required String dateKey,
    required String currentUserId,
    required String excludeRequestId,
  }) {
    Future(() async {
      try {
        // Expire pending requests TO current user (they can't accept anymore)
        final toSnapshot = await _requestsCol(dateKey)
            .where('receiverId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'pending')
            .get();

        if (toSnapshot.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in toSnapshot.docs) {
            if (doc.id == excludeRequestId) continue;
            batch.update(doc.reference, {
              'status': 'expired',
              'respondedAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }

        // Expire pending requests FROM current user (receivers can't accept
        // these since current user now has an active connection)
        final fromSnapshot = await _requestsCol(dateKey)
            .where('senderId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'pending')
            .get();

        if (fromSnapshot.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in fromSnapshot.docs) {
            if (doc.id == excludeRequestId) continue;
            batch.update(doc.reference, {
              'status': 'expired',
              'respondedAt': FieldValue.serverTimestamp(),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        _logger.w('Failed to auto-expire pending requests', error: e);
      }
    });
  }
}
