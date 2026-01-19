import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/guess_me_session.dart';
import '../domain/entities/guess_me_stats.dart';
import 'models/guess_me_models.dart';
import 'models/guess_me_stats_model.dart';

/// Service for managing GuessMe game sessions.
class GuessmeService {
  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  /// Session duration: 1 hour
  static const sessionDuration = Duration(hours: 1);

  /// Queue timeout: 5 minutes
  static const queueTimeout = Duration(minutes: 5);

  CollectionReference<Map<String, dynamic>> get _sessionsRef =>
      _firestore.collection('guess_me_sessions');

  CollectionReference<Map<String, dynamic>> get _queueRef =>
      _firestore.collection('guess_me_queue');

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _firestore.collection('guess_me_messages');

  GuessmeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ==================== GAME STATUS MANAGEMENT ====================

  /// Sets user's game status to indicate they're in a GuessMe game.
  Future<void> _setUserInGame(String userId, String sessionId) async {
    try {
      await _firestore.collection('profiles').doc(userId).update({
        'isInGuessMeGame': true,
        'guessMeSessionId': sessionId,
        'guessMeJoinedAt': FieldValue.serverTimestamp(),
      });
      _logger.d('Set user $userId in game status');
    } catch (e) {
      _logger.w('Error setting user game status', error: e);
      // Non-critical, don't rethrow
    }
  }

  /// Clears user's game status.
  Future<void> _clearUserGameStatus(String userId) async {
    try {
      await _firestore.collection('profiles').doc(userId).update({
        'isInGuessMeGame': false,
        'guessMeSessionId': FieldValue.delete(),
        'guessMeJoinedAt': FieldValue.delete(),
      });
      _logger.d('Cleared user $userId game status');
    } catch (e) {
      _logger.w('Error clearing user game status', error: e);
      // Non-critical, don't rethrow
    }
  }

  /// Public method to clear user's game status (for app lifecycle cleanup).
  Future<void> clearUserGameStatus(String userId) async {
    await _clearUserGameStatus(userId);
  }

  /// Checks if a user is available for matching (not in game, not in queue).
  Future<bool> _isUserAvailable(String userId) async {
    try {
      // Check if user has an active session
      final sessionQuery = await _sessionsRef
          .where('players', arrayContains: userId)
          .where('status', isEqualTo: GuessmeSessionStatus.active.name)
          .limit(1)
          .get();
      
      if (sessionQuery.docs.isNotEmpty) {
        return false;
      }

      // Check profile status
      final profileDoc = await _firestore.collection('profiles').doc(userId).get();
      if (profileDoc.exists) {
        final data = profileDoc.data();
        final isInGame = data?['isInGuessMeGame'] as bool? ?? false;
        if (isInGame) {
          return false;
        }
      }

      // User in queue IS available for matching!
      // Only unavailable if they're already in an active game
      return true;
    } catch (e) {
      _logger.w('Error checking user availability for $userId', error: e);
      return false;
    }
  }

  // ==================== QUEUE MANAGEMENT ====================

  /// Joins the matchmaking queue.
  /// Returns session ID if immediately matched, null if waiting.
  Future<String?> joinQueue({
    required String userId,
    required List<String> nearbyUserIds,
  }) async {
    try {
      // First, check if user already has an active session
      final existingSession = await getActiveSession(userId);
      if (existingSession != null) {
        _logger.i(
            'User $userId already has active session: ${existingSession.id}');
        return existingSession.id;
      }

      // Check if already in queue
      final existingQueueEntry = await _queueRef.doc(userId).get();
      if (existingQueueEntry.exists) {
        _logger.i('User $userId already in queue');
        // Still try to find a match from updated nearby list
      }

      _logger.i('Attempting to match user $userId with ${nearbyUserIds.length} nearby users');

      // Try to find ONE available nearby user to match with
      // This works like the Nearby page - automatically select first available user
      for (final nearbyUserId in nearbyUserIds) {
        // Skip self
        if (nearbyUserId == userId) continue;

        // Check if this user is available
        final isAvailable = await _isUserAvailable(nearbyUserId);
        if (!isAvailable) {
          _logger.d('User $nearbyUserId is not available for matching');
          continue;
        }

        // Found an available user! Create session immediately
        _logger.i('Found available user $nearbyUserId, creating session');
        final sessionId = await _createSession(userId, nearbyUserId);

        // Remove both users from queue if they were in queue
        await Future.wait([
          if (existingQueueEntry.exists) _queueRef.doc(userId).delete(),
          _queueRef.doc(nearbyUserId).delete(), // Remove matched user from queue too
        ]);

        // Set both users' game status
        await Future.wait([
          _setUserInGame(userId, sessionId),
          _setUserInGame(nearbyUserId, sessionId),
        ]);

        return sessionId;
      }

      // No available users found, add to queue to wait
      _logger.i('No available users found, adding $userId to queue');
      final queueEntry = {
        'userId': userId,
        'nearbyUserIds': nearbyUserIds,
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(queueTimeout)),
      };

      await _queueRef.doc(userId).set(queueEntry);
      _logger.i('User $userId joined queue');
      return null;
    } catch (e, stack) {
      _logger.e('Error joining queue', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Leaves the matchmaking queue.
  Future<void> leaveQueue(String userId) async {
    try {
      await _queueRef.doc(userId).delete();
      _logger.i('User $userId left queue');
    } catch (e, stack) {
      _logger.e('Error leaving queue', error: e, stackTrace: stack);
    }
  }

  /// Stream of queue status for a user.
  Stream<bool> getQueueStatusStream(String userId) {
    return _queueRef.doc(userId).snapshots().map((doc) => doc.exists);
  }

  /// Stream that detects when a user gets an active session.
  /// Used to monitor when a queued user gets matched.
  Stream<GuessmeSession?> getActiveSessionStream(String userId) {
    return _sessionsRef
        .where('players', arrayContains: userId)
        .where('status', isEqualTo: GuessmeSessionStatus.active.name)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return GuessmeSessionModel.fromFirestore(snapshot.docs.first).toEntity();
        });
  }

  // ==================== SESSION MANAGEMENT ====================

  /// Fetches a user's display name from their profile.
  Future<String?> _getUserDisplayName(String userId) async {
    try {
      final profileDoc =
          await _firestore.collection('profiles').doc(userId).get();
      if (profileDoc.exists) {
        final data = profileDoc.data();
        return data?['displayName'] as String? ?? data?['name'] as String?;
      }
      return null;
    } catch (e) {
      _logger.w('Error fetching display name for $userId', error: e);
      return null;
    }
  }

  /// Creates a new game session.
  Future<String> _createSession(String player1Id, String player2Id) async {
    final now = DateTime.now();
    final sessionId = _sessionsRef.doc().id;

    // Fetch player names
    final player1Name = await _getUserDisplayName(player1Id);
    final player2Name = await _getUserDisplayName(player2Id);

    final session = GuessmeSessionModel(
      id: sessionId,
      player1Id: player1Id,
      player1Name: player1Name,
      player2Id: player2Id,
      player2Name: player2Name,
      status: GuessmeSessionStatus.active,
      createdAt: now,
      startedAt: now,
      expiresAt: now.add(sessionDuration),
    );

    await _sessionsRef.doc(sessionId).set(session.toFirestore());

    // Send system message
    await sendSystemMessage(
      sessionId: sessionId,
      text:
          '🎮 Game started! You have 1 hour to chat and guess who the other person is. Good luck!',
    );

    return sessionId;
  }

  /// Gets a session by ID.
  Future<GuessmeSession?> getSession(String sessionId) async {
    try {
      final doc = await _sessionsRef.doc(sessionId).get();
      if (!doc.exists) return null;
      return GuessmeSessionModel.fromFirestore(doc).toEntity();
    } catch (e, stack) {
      _logger.e('Error getting session', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Gets user's active session (if any).
  Future<GuessmeSession?> getActiveSession(String userId) async {
    try {
      final query = await _sessionsRef
          .where('players', arrayContains: userId)
          .where('status', isEqualTo: GuessmeSessionStatus.active.name)
          .limit(1)
          .get();

      if (query.docs.isEmpty) return null;

      final session =
          GuessmeSessionModel.fromFirestore(query.docs.first).toEntity();

      // Check if session has expired
      if (session.expiresAt != null &&
          DateTime.now().isAfter(session.expiresAt!)) {
        await expireSession(session.id);
        return null;
      }

      return session;
    } catch (e, stack) {
      _logger.e('Error getting active session', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Stream of session updates.
  Stream<GuessmeSession?> getSessionStream(String sessionId) {
    return _sessionsRef.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return GuessmeSessionModel.fromFirestore(doc).toEntity();
    });
  }

  /// Cancels/leaves a session.
  Future<void> cancelSession(String sessionId, String userId) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) return;

      await _sessionsRef.doc(sessionId).update({
        'status': GuessmeSessionStatus.cancelled.name,
        'endedAt': FieldValue.serverTimestamp(),
      });

      await sendSystemMessage(
        sessionId: sessionId,
        text: '👋 The other player has left the game.',
      );

      // Update stats for both players (game played without completing)
      await Future.wait([
        incrementGamesPlayedNoGuess(session.player1Id),
        if (session.player2Id != null) incrementGamesPlayedNoGuess(session.player2Id!),
      ]);

      // Clear game status for both players
      await Future.wait([
        _clearUserGameStatus(session.player1Id),
        if (session.player2Id != null) _clearUserGameStatus(session.player2Id!),
      ]);

      _logger.i('Session $sessionId cancelled by $userId');
    } catch (e, stack) {
      _logger.e('Error cancelling session', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Expires a session.
  Future<void> expireSession(String sessionId) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) return;

      await _sessionsRef.doc(sessionId).update({
        'status': GuessmeSessionStatus.expired.name,
        'endedAt': FieldValue.serverTimestamp(),
      });

      // Update stats for both players (game played without correct guess)
      await Future.wait([
        incrementGamesPlayedNoGuess(session.player1Id),
        if (session.player2Id != null) incrementGamesPlayedNoGuess(session.player2Id!),
      ]);

      // Clear game status for both players
      await Future.wait([
        _clearUserGameStatus(session.player1Id),
        if (session.player2Id != null) _clearUserGameStatus(session.player2Id!),
      ]);

      _logger.i('Session $sessionId expired');
    } catch (e, stack) {
      _logger.e('Error expiring session', error: e, stackTrace: stack);
    }
  }

  // ==================== GUESS MECHANISM ====================

  /// Initiates a guess check.
  Future<void> initiateGuessCheck(String sessionId, String initiatorId) async {
    try {
      await _sessionsRef.doc(sessionId).update({
        'guessCheckInitiator': initiatorId,
        'guessCheckPending': true,
      });

      await sendSystemMessage(
        sessionId: sessionId,
        text:
            '🤔 A player thinks they know who you are! Please confirm if they guessed correctly.',
      );

      _logger.i('Guess check initiated in session $sessionId by $initiatorId');
    } catch (e, stack) {
      _logger.e('Error initiating guess check', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Responds to a guess check.
  Future<bool> respondToGuessCheck({
    required String sessionId,
    required String responderId,
    required bool isCorrect,
  }) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) throw Exception('Session not found');

      final initiatorId = session.guessCheckInitiator;
      if (initiatorId == null) {
        throw Exception('No guess check in progress');
      }

      // Update session based on response
      final updates = <String, dynamic>{
        'guessCheckPending': false,
        'guessCheckInitiator': null,
      };

      if (isCorrect) {
        // Mark the responder as guessed
        if (responderId == session.player1Id) {
          updates['player1Guessed'] = true;
        } else if (responderId == session.player2Id) {
          updates['player2Guessed'] = true;
        }

        // If both are now guessed, complete the session
        final bothGuessed = (session.player1Guessed ||
                (responderId == session.player1Id)) &&
            (session.player2Guessed || (responderId == session.player2Id));

        if (bothGuessed) {
          updates['status'] = GuessmeSessionStatus.completed.name;
          updates['endedAt'] = FieldValue.serverTimestamp();
          
          // Clear game status for both players when game completes
          await Future.wait([
            _clearUserGameStatus(session.player1Id),
            if (session.player2Id != null) _clearUserGameStatus(session.player2Id!),
          ]);
        }

        // Update stats
        await _incrementCorrectGuess(initiatorId);
        await _incrementTimesGuessed(responderId);

        await sendSystemMessage(
          sessionId: sessionId,
          text:
              '🎉 Correct! ${session.getPlayerDisplayName(initiatorId)} guessed who ${session.getPlayerDisplayName(responderId)} is!',
        );
      } else {
        await sendSystemMessage(
          sessionId: sessionId,
          text: '❌ Not quite! Keep chatting and try again later.',
        );
      }

      await _sessionsRef.doc(sessionId).update(updates);

      _logger.i('Guess check response: ${isCorrect ? "correct" : "incorrect"}');
      return isCorrect;
    } catch (e, stack) {
      _logger.e('Error responding to guess check', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== MESSAGING ====================

  /// Sends a chat message.
  Future<void> sendMessage({
    required String sessionId,
    required String senderId,
    required String text,
  }) async {
    try {
      final messageId = _messagesRef.doc().id;

      final message = GuessmeMessageModel(
        id: messageId,
        sessionId: sessionId,
        senderId: senderId,
        text: text,
        sentAt: DateTime.now(),
      );

      await _messagesRef
          .doc(messageId)
          .set(message.toFirestore(useServerTimestamp: true));
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Sends a system message.
  Future<void> sendSystemMessage({
    required String sessionId,
    required String text,
  }) async {
    try {
      final messageId = _messagesRef.doc().id;

      final message = GuessmeMessageModel(
        id: messageId,
        sessionId: sessionId,
        senderId: 'system',
        text: text,
        sentAt: DateTime.now(),
        type: GuessmeMessageType.system,
      );

      await _messagesRef
          .doc(messageId)
          .set(message.toFirestore(useServerTimestamp: true));
    } catch (e, stack) {
      _logger.e('Error sending system message', error: e, stackTrace: stack);
    }
  }

  /// Stream of messages for a session.
  Stream<List<GuessmeMessage>> getMessagesStream(String sessionId) {
    return _messagesRef
        .where('sessionId', isEqualTo: sessionId)
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => GuessmeMessageModel.fromFirestore(doc).toEntity())
            .toList());
  }

  // ==================== STATS ====================

  /// Gets user's GuessMe stats.
  Future<GuessmeStats> getStats(String userId) async {
    try {
      final doc = await _firestore
          .collection('profiles')
          .doc(userId)
          .collection('stats')
          .doc('guess_me')
          .get();

      if (!doc.exists) return const GuessmeStats();
      return GuessmeStatsModel.fromFirestore(doc).toEntity();
    } catch (e, stack) {
      _logger.e('Error getting stats', error: e, stackTrace: stack);
      return const GuessmeStats();
    }
  }

  /// Stream of user's stats.
  Stream<GuessmeStats> getStatsStream(String userId) {
    return _firestore
        .collection('profiles')
        .doc(userId)
        .collection('stats')
        .doc('guess_me')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return const GuessmeStats();
      return GuessmeStatsModel.fromFirestore(doc).toEntity();
    });
  }

  /// Increments correct guess count.
  Future<void> _incrementCorrectGuess(String userId) async {
    try {
      final statsRef = _firestore
          .collection('profiles')
          .doc(userId)
          .collection('stats')
          .doc('guess_me');

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(statsRef);
        final currentStats = doc.exists
            ? GuessmeStatsModel.fromFirestore(doc)
            : const GuessmeStatsModel();

        final newStreak = currentStats.currentStreak + 1;
        final newBestStreak = newStreak > currentStats.bestStreak
            ? newStreak
            : currentStats.bestStreak;

        final updatedStats = GuessmeStatsModel(
          gamesPlayed: currentStats.gamesPlayed + 1,
          correctGuesses: currentStats.correctGuesses + 1,
          timesGuessed: currentStats.timesGuessed,
          currentStreak: newStreak,
          bestStreak: newBestStreak,
          lastPlayed: DateTime.now(),
        );

        transaction.set(statsRef, updatedStats.toFirestore());
      });

      // Also update the badge count on the public profile
      await _updatePublicBadgeCount(userId);

      _logger.i('Incremented correct guess for $userId');
    } catch (e, stack) {
      _logger.e('Error incrementing correct guess',
          error: e, stackTrace: stack);
    }
  }

  /// Increments times guessed count.
  Future<void> _incrementTimesGuessed(String userId) async {
    try {
      final statsRef = _firestore
          .collection('profiles')
          .doc(userId)
          .collection('stats')
          .doc('guess_me');

      await statsRef.set({
        'timesGuessed': FieldValue.increment(1),
        'lastPlayed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _logger.i('Incremented times guessed for $userId');
    } catch (e, stack) {
      _logger.e('Error incrementing times guessed',
          error: e, stackTrace: stack);
    }
  }

  /// Updates the public badge count on profile.
  Future<void> _updatePublicBadgeCount(String userId) async {
    try {
      final stats = await getStats(userId);
      await _firestore.collection('profiles').doc(userId).update({
        'guessmeCorrectGuesses': stats.correctGuesses,
      });
    } catch (e, stack) {
      _logger.e('Error updating public badge count',
          error: e, stackTrace: stack);
    }
  }

  /// Increments games played without a correct guess (resets streak).
  Future<void> incrementGamesPlayedNoGuess(String userId) async {
    try {
      final statsRef = _firestore
          .collection('profiles')
          .doc(userId)
          .collection('stats')
          .doc('guess_me');

      await statsRef.set({
        'gamesPlayed': FieldValue.increment(1),
        'currentStreak': 0, // Reset streak
        'lastPlayed': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _logger.i('Incremented games played for $userId');
    } catch (e, stack) {
      _logger.e('Error incrementing games played', error: e, stackTrace: stack);
    }
  }
}
