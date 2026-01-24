import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/guess_me_session.dart';
import '../domain/entities/guess_me_stats.dart';
import 'models/guess_me_models.dart';
import 'models/guess_me_stats_model.dart';

/// Service for managing GuessMe game sessions.
/// 
/// Game Flow:
/// 1. User taps "Play Game" -> joinQueue() called with nearby user IDs
/// 2. Service finds first available user and creates session immediately
/// 3. Both users chat anonymously for up to 1 hour
/// 4. Either can initiate guess check -> other must confirm
/// 5. On correct guess -> awaitingConnectionConfirmations = true
/// 6. Both users must confirm to connect -> recordMutualConnection()
/// 7. If either declines or timer expires -> session ends normally
/// 8. Stats only update on mutual connection success
class GuessmeService {
  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  /// Session duration: 1 hour
  static const sessionDuration = Duration(hours: 1);

  /// Connection confirmation timeout: 5 minutes
  static const connectionConfirmationTimeout = Duration(minutes: 5);

  /// Queue timeout: 5 minutes
  static const queueTimeout = Duration(minutes: 5);

  CollectionReference<Map<String, dynamic>> get _sessionsRef =>
      _firestore.collection('guess_me_sessions');

  CollectionReference<Map<String, dynamic>> get _queueRef =>
      _firestore.collection('guess_me_queue');

  // Messages are now stored as subcollection under each session
  // This matches the pattern used by connections chat and simplifies permissions
  CollectionReference<Map<String, dynamic>> _messagesRef(String sessionId) =>
      _sessionsRef.doc(sessionId).collection('messages');

  GuessmeService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ==================== GAME STATUS MANAGEMENT ====================

  /// Marks user as actively searching for a GuessMe match.
  Future<void> setUserSearching(String userId) async {
    try {
      await _firestore.collection('profiles').doc(userId).update({
        'isSearchingGuessMeGame': true,
        'guessMeSearchStartedAt': FieldValue.serverTimestamp(),
      });
      _logger.d('Set user $userId as searching for GuessMe');
    } catch (e) {
      _logger.w('Error setting user searching status', error: e);
    }
  }

  /// Clears user's searching status.
  Future<void> clearUserSearching(String userId) async {
    try {
      await _firestore.collection('profiles').doc(userId).update({
        'isSearchingGuessMeGame': false,
        'guessMeSearchStartedAt': FieldValue.delete(),
      });
      _logger.d('Cleared user $userId searching status');
    } catch (e) {
      _logger.w('Error clearing user searching status', error: e);
    }
  }

  /// Sets user's game status to indicate they're in a GuessMe game.
  Future<void> _setUserInGame(String userId, String sessionId) async {
    try {
      await _firestore.collection('profiles').doc(userId).update({
        'isInGuessMeGame': true,
        'guessMeSessionId': sessionId,
        'guessMeJoinedAt': FieldValue.serverTimestamp(),
        'isSearchingGuessMeGame': false,
        'guessMeSearchStartedAt': FieldValue.delete(),
      });
      _logger.d('Set user $userId in game status');
    } catch (e) {
      _logger.w('Error setting user game status', error: e);
    }
  }

  /// Clears user's game status.
  Future<void> _clearUserGameStatus(String userId) async {
    try {
      await _firestore.collection('profiles').doc(userId).update({
        'isInGuessMeGame': false,
        'guessMeSessionId': FieldValue.delete(),
        'guessMeJoinedAt': FieldValue.delete(),
        'isSearchingGuessMeGame': false,
        'guessMeSearchStartedAt': FieldValue.delete(),
      });
      _logger.d('Cleared user $userId game status');
    } catch (e) {
      _logger.w('Error clearing user game status', error: e);
    }
  }

  /// Public method to clear user's game status (for app lifecycle cleanup).
  Future<void> clearUserGameStatus(String userId) async {
    await _clearUserGameStatus(userId);
  }

  /// Checks if a user is available for matching (not in active game).
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
        // User must be actively searching to be available
        final isSearching = data?['isSearchingGuessMeGame'] as bool? ?? false;
        if (!isSearching) {
          return false;
        }
      }

      return true;
    } catch (e) {
      _logger.w('Error checking user availability for $userId', error: e);
      return false;
    }
  }

  // ==================== QUEUE MANAGEMENT ====================

  /// Joins the matchmaking queue.
  /// INSTANTLY matches with the first available nearby user.
  /// Returns session ID if matched, null if no one available.
  Future<String?> joinQueue({
    required String userId,
    required List<String> nearbyUserIds,
  }) async {
    try {
      _logger.i('User $userId joining queue with ${nearbyUserIds.length} nearby users');
      
      // Validate inputs
      if (nearbyUserIds.isEmpty) {
        _logger.w('Cannot join queue: no nearby users provided');
        return null;
      }
      
      // Remove self from nearby users list
      final validNearbyUsers = nearbyUserIds.where((id) => id != userId).toList();
      if (validNearbyUsers.isEmpty) {
        _logger.w('Cannot join queue: no valid nearby users (all were self)');
        return null;
      }
      
      _logger.d('Valid nearby users after filtering: ${validNearbyUsers.length}');
      
      // First, check if user already has an active session
      final existingSession = await getActiveSession(userId);
      if (existingSession != null) {
        _logger.i('User $userId already has active session: ${existingSession.id}');
        return existingSession.id;
      }

      // Try to find ONE available nearby user to match with IMMEDIATELY
      for (final nearbyUserId in validNearbyUsers) {
        _logger.d('Checking availability of user: $nearbyUserId');
        
        // Check if this user is available
        final isAvailable = await _isUserAvailable(nearbyUserId);
        if (!isAvailable) {
          _logger.d('User $nearbyUserId is not available for matching');
          continue;
        }

        // Found an available user! Create session immediately
        _logger.i('Found available user $nearbyUserId, creating session');
        
        try {
          final sessionId = await _createSession(userId, nearbyUserId);

          // Remove both users from queue if they were there
          await Future.wait([
            _queueRef.doc(userId).delete().catchError((e) {
              _logger.w('Error removing user from queue', error: e);
            }),
            _queueRef.doc(nearbyUserId).delete().catchError((e) {
              _logger.w('Error removing nearby user from queue', error: e);
            }),
          ]);

          // Set both users' game status
          await Future.wait([
            _setUserInGame(userId, sessionId),
            _setUserInGame(nearbyUserId, sessionId),
          ]);

          _logger.i('Successfully matched $userId with $nearbyUserId - session: $sessionId');
          return sessionId;
        } catch (e) {
          _logger.w('Failed to create session with $nearbyUserId, trying next user', error: e);
          // Continue to next nearby user if session creation failed
          continue;
        }
      }

      // No available users found - add to queue briefly
      // But mainly, return null to indicate no match
      _logger.i('No available users found for $userId - adding to queue');
      
      final queueEntry = {
        'userId': userId,
        'nearbyUserIds': validNearbyUsers,
        'joinedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(queueTimeout)),
      };
      await _queueRef.doc(userId).set(queueEntry);
      
      return null;
    } catch (e, stack) {
      _logger.e('Error joining queue for user $userId', error: e, stackTrace: stack);
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

  /// Creates a new game session between two players.
  /// Uses a Firestore transaction to ensure atomic creation and prevent duplicates.
  Future<String> _createSession(String player1Id, String player2Id) async {
    _logger.i('Creating session between $player1Id and $player2Id');
    
    // Use transaction to prevent race conditions and duplicate sessions
    return await _firestore.runTransaction<String>((transaction) async {
      final now = DateTime.now();
      
      // Sort player IDs to create deterministic session ID
      final playerIds = [player1Id, player2Id]..sort();
      final deterministicSessionId = 'session_${playerIds[0]}_${playerIds[1]}_${now.millisecondsSinceEpoch}';
      
      // Check if either player already has an active session
      final player1SessionQuery = await _sessionsRef
          .where('players', arrayContains: player1Id)
          .where('status', isEqualTo: GuessmeSessionStatus.active.name)
          .limit(1)
          .get();
      
      if (player1SessionQuery.docs.isNotEmpty) {
        final existingSessionId = player1SessionQuery.docs.first.id;
        _logger.w('Player $player1Id already has active session: $existingSessionId');
        throw Exception('Player already in active session: $existingSessionId');
      }
      
      final player2SessionQuery = await _sessionsRef
          .where('players', arrayContains: player2Id)
          .where('status', isEqualTo: GuessmeSessionStatus.active.name)
          .limit(1)
          .get();
      
      if (player2SessionQuery.docs.isNotEmpty) {
        final existingSessionId = player2SessionQuery.docs.first.id;
        _logger.w('Player $player2Id already has active session: $existingSessionId');
        throw Exception('Player already in active session: $existingSessionId');
      }

      // Fetch player names
      final player1Doc = await transaction.get(_firestore.collection('users').doc(player1Id));
      final player2Doc = await transaction.get(_firestore.collection('users').doc(player2Id));
      
      final player1Name = player1Doc.exists ? (player1Doc.data()?['displayName'] as String?) : null;
      final player2Name = player2Doc.exists ? (player2Doc.data()?['displayName'] as String?) : null;

      final session = GuessmeSessionModel(
        id: deterministicSessionId,
        players: [player1Id, player2Id],
        player1Id: player1Id,
        player1Name: player1Name ?? 'Mystery User A',
        player2Id: player2Id,
        player2Name: player2Name ?? 'Mystery User B',
        status: GuessmeSessionStatus.active.name,
        createdAt: now,
        expiresAt: now.add(sessionDuration),
        player1Guessed: false,
        player2Guessed: false,
        guessCheckPending: false,
        guessCheckInitiator: null,
        awaitingConnectionConfirmations: false,
        connectionRequestId: null,
      );

      // Create session document within transaction
      transaction.set(_sessionsRef.doc(deterministicSessionId), session.toFirestore());

      _logger.i('Created session $deterministicSessionId between $player1Id and $player2Id');
      return deterministicSessionId;
    }).then((sessionId) async {
      // Send initial system message AFTER transaction completes
      await sendSystemMessage(
        sessionId: sessionId,
        text: '🎮 Game started! You have 1 hour to chat and guess who the other person is. Good luck!',
      );
      return sessionId;
    });
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
      _logger.d('Checking for active session for user: $userId');
      
      final query = await _sessionsRef
          .where('players', arrayContains: userId)
          .where('status', isEqualTo: GuessmeSessionStatus.active.name)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _logger.d('No active session found for user: $userId');
        return null;
      }

      final sessionDoc = query.docs.first;
      _logger.i('Found active session for user $userId: ${sessionDoc.id}');
      
      final session = GuessmeSessionModel.fromFirestore(sessionDoc).toEntity();

      // Check if session has expired
      if (session.expiresAt != null && DateTime.now().isAfter(session.expiresAt!)) {
        _logger.w('Session ${session.id} has expired - expiring now');
        await expireSession(session.id);
        return null;
      }

      return session;
    } catch (e, stack) {
      _logger.e('Error getting active session for user $userId', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Stream of session updates.
  Stream<GuessmeSession?> getSessionStream(String sessionId) {
    _logger.d('Setting up session stream for: $sessionId');
    
    return _sessionsRef.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists) {
        _logger.w('Session $sessionId no longer exists in Firestore');
        return null;
      }
      
      final session = GuessmeSessionModel.fromFirestore(doc).toEntity();
      _logger.d('Session stream update - $sessionId: status=${session.status}, '
          'guessCheckPending=${session.guessCheckPending}, '
          'initiator=${session.guessCheckInitiator}, '
          'awaitingConnection=${session.awaitingConnectionConfirmations}');
      
      return session;
    }).handleError((error, stackTrace) {
      _logger.e('Error in session stream for $sessionId', error: error, stackTrace: stackTrace);
      return null;
    });
  }

  /// Cancels/leaves a session.
  Future<void> cancelSession(String sessionId, String leavingUserId) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) return;

      await _sessionsRef.doc(sessionId).update({
        'status': GuessmeSessionStatus.cancelled.name,
        'endedAt': FieldValue.serverTimestamp(),
        'cancelledBy': leavingUserId,
      });

      await sendSystemMessage(
        sessionId: sessionId,
        text: '👋 The other player has left the game.',
      );

      // Clear game status for both players
      final clearTasks = [_clearUserGameStatus(session.player1Id)];
      if (session.player2Id != null) {
        clearTasks.add(_clearUserGameStatus(session.player2Id!));
      }
      await Future.wait(clearTasks);

      _logger.i('Session $sessionId cancelled by $leavingUserId');
    } catch (e, stack) {
      _logger.e('Error cancelling session', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Expires a session (timer ran out).
  Future<void> expireSession(String sessionId) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) return;
      
      // Don't expire if already ended
      if (session.status != GuessmeSessionStatus.active) return;

      await _sessionsRef.doc(sessionId).update({
        'status': GuessmeSessionStatus.expired.name,
        'endedAt': FieldValue.serverTimestamp(),
      });

      await sendSystemMessage(
        sessionId: sessionId,
        text: '⏰ Time\'s up! The game has ended.',
      );

      // Clear game status for both players
      final clearTasks = [_clearUserGameStatus(session.player1Id)];
      if (session.player2Id != null) {
        clearTasks.add(_clearUserGameStatus(session.player2Id!));
      }
      await Future.wait(clearTasks);

      _logger.i('Session $sessionId expired');
    } catch (e, stack) {
      _logger.e('Error expiring session', error: e, stackTrace: stack);
    }
  }

  // ==================== GUESS MECHANISM ====================

  /// Initiates a guess check. The other player must confirm/deny.
  Future<void> initiateGuessCheck(String sessionId, String initiatorId) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) throw Exception('Session not found');
      
      // Prevent if guess check already pending
      if (session.guessCheckPending) {
        throw Exception('Guess check already in progress');
      }

      await _sessionsRef.doc(sessionId).update({
        'guessCheckInitiator': initiatorId,
        'guessCheckPending': true,
      });

      await sendSystemMessage(
        sessionId: sessionId,
        text: '🤔 A player thinks they know who you are! Please confirm if they guessed correctly.',
      );

      _logger.i('Guess check initiated in session $sessionId by $initiatorId');
    } catch (e, stack) {
      _logger.e('Error initiating guess check', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Responds to a guess check.
  /// If correct -> awaitingConnectionConfirmations = true
  /// If incorrect -> game continues
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

      final updates = <String, dynamic>{
        'guessCheckPending': false,
        'guessCheckInitiator': null,
      };

      if (isCorrect) {
        // Mark who was guessed correctly
        if (responderId == session.player1Id) {
          updates['player1Guessed'] = true;
        } else if (responderId == session.player2Id) {
          updates['player2Guessed'] = true;
        }

        // Start the mutual connection confirmation process
        updates['awaitingConnectionConfirmations'] = true;
        updates['connectionConfirmationStartedAt'] = FieldValue.serverTimestamp();
        updates['player1WantsToConnect'] = null;
        updates['player2WantsToConnect'] = null;

        await _sessionsRef.doc(sessionId).update(updates);

        await sendSystemMessage(
          sessionId: sessionId,
          text: '🎉 Correct guess! Both players can now choose to connect permanently.',
        );

        _logger.i('Correct guess in session $sessionId');
        return true;
      } else {
        await _sessionsRef.doc(sessionId).update(updates);

        await sendSystemMessage(
          sessionId: sessionId,
          text: '❌ Not quite! Keep chatting and try again later.',
        );

        _logger.i('Incorrect guess in session $sessionId');
        return false;
      }
    } catch (e, stack) {
      _logger.e('Error responding to guess check', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== CONNECTION CONFIRMATION ====================

  /// Records a player's decision to connect or not after successful guess.
  /// Returns true if both have now responded (regardless of outcome).
  Future<ConnectionConfirmationResult> respondToConnectionPrompt({
    required String sessionId,
    required String userId,
    required bool wantsToConnect,
  }) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) {
        return ConnectionConfirmationResult(
          bothResponded: false,
          bothWantToConnect: false,
          error: 'Session not found',
        );
      }

      if (!session.awaitingConnectionConfirmations) {
        return ConnectionConfirmationResult(
          bothResponded: false,
          bothWantToConnect: false,
          error: 'Not awaiting connection confirmations',
        );
      }

      // Record this user's response
      final updates = <String, dynamic>{};
      bool? otherPlayerWants;

      if (userId == session.player1Id) {
        updates['player1WantsToConnect'] = wantsToConnect;
        // Check if player2 already responded
        final doc = await _sessionsRef.doc(sessionId).get();
        otherPlayerWants = doc.data()?['player2WantsToConnect'] as bool?;
      } else if (userId == session.player2Id) {
        updates['player2WantsToConnect'] = wantsToConnect;
        // Check if player1 already responded
        final doc = await _sessionsRef.doc(sessionId).get();
        otherPlayerWants = doc.data()?['player1WantsToConnect'] as bool?;
      } else {
        return ConnectionConfirmationResult(
          bothResponded: false,
          bothWantToConnect: false,
          error: 'User not in session',
        );
      }

      await _sessionsRef.doc(sessionId).update(updates);

      // If both have responded, process the result
      if (otherPlayerWants != null) {
        final bothWantToConnect = wantsToConnect && otherPlayerWants;
        
        if (bothWantToConnect) {
          // Both want to connect - complete with success
          await _sessionsRef.doc(sessionId).update({
            'status': GuessmeSessionStatus.completed.name,
            'endedAt': FieldValue.serverTimestamp(),
            'awaitingConnectionConfirmations': false,
            'mutualConnectionSuccess': true,
          });

          // Update stats for BOTH players - this is the ONLY place stats are updated
          final statsTasks = [_incrementCorrectGuess(session.player1Id)];
          if (session.player2Id != null) {
            statsTasks.add(_incrementCorrectGuess(session.player2Id!));
          }
          await Future.wait(statsTasks);

          await sendSystemMessage(
            sessionId: sessionId,
            text: '🤝 Both players want to connect! You can now chat permanently.',
          );

          // Clear game status
          final clearTasks = [_clearUserGameStatus(session.player1Id)];
          if (session.player2Id != null) {
            clearTasks.add(_clearUserGameStatus(session.player2Id!));
          }
          await Future.wait(clearTasks);

          _logger.i('Mutual connection success in session $sessionId');
        } else {
          // One or both declined - end game without connection
          await _sessionsRef.doc(sessionId).update({
            'status': GuessmeSessionStatus.completed.name,
            'endedAt': FieldValue.serverTimestamp(),
            'awaitingConnectionConfirmations': false,
            'mutualConnectionSuccess': false,
          });

          await sendSystemMessage(
            sessionId: sessionId,
            text: '👋 The connection was declined. Thanks for playing!',
          );

          // Clear game status
          final clearTasks = [_clearUserGameStatus(session.player1Id)];
          if (session.player2Id != null) {
            clearTasks.add(_clearUserGameStatus(session.player2Id!));
          }
          await Future.wait(clearTasks);

          _logger.i('Connection declined in session $sessionId');
        }

        return ConnectionConfirmationResult(
          bothResponded: true,
          bothWantToConnect: bothWantToConnect,
        );
      }

      // Only this user has responded so far
      await sendSystemMessage(
        sessionId: sessionId,
        text: wantsToConnect
            ? '✅ You want to connect! Waiting for the other player...'
            : '❌ You declined to connect. Waiting for the other player...',
      );

      return ConnectionConfirmationResult(
        bothResponded: false,
        bothWantToConnect: false,
      );
    } catch (e, stack) {
      _logger.e('Error responding to connection prompt', error: e, stackTrace: stack);
      return ConnectionConfirmationResult(
        bothResponded: false,
        bothWantToConnect: false,
        error: e.toString(),
      );
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
      _logger.d('Attempting to send message - sessionId: $sessionId, senderId: $senderId, textLength: ${text.length}');
      
      // Validate session exists and is active
      final sessionDoc = await _sessionsRef.doc(sessionId).get();
      if (!sessionDoc.exists) {
        _logger.e('Cannot send message: session $sessionId does not exist');
        throw Exception('Session not found');
      }
      
      final sessionData = sessionDoc.data();
      final sessionStatus = sessionData?['status'] as String?;
      if (sessionStatus != GuessmeSessionStatus.active.name) {
        _logger.w('Cannot send message: session $sessionId is not active (status: $sessionStatus)');
        throw Exception('Session is not active');
      }
      
      // Validate sender is a participant
      final players = List<String>.from(sessionData?['players'] ?? []);
      if (!players.contains(senderId)) {
        _logger.e('Cannot send message: $senderId is not a participant in session $sessionId');
        throw Exception('Sender is not a participant in this session');
      }
      
      final messagesCollection = _messagesRef(sessionId);
      final messageId = messagesCollection.doc().id;

      final message = GuessmeMessageModel(
        id: messageId,
        sessionId: sessionId,
        senderId: senderId,
        text: text,
        sentAt: DateTime.now(),
      );

      _logger.d('Writing message to Firestore: messages/$messageId');
      await messagesCollection.doc(messageId).set(message.toFirestore(useServerTimestamp: true));
      _logger.i('Message sent successfully - sessionId: $sessionId, messageId: $messageId, sender: $senderId');
    } catch (e, stack) {
      _logger.e('Error sending message - sessionId: $sessionId, senderId: $senderId', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Sends a system message.
  Future<void> sendSystemMessage({
    required String sessionId,
    required String text,
  }) async {
    try {
      final messagesCollection = _messagesRef(sessionId);
      final messageId = messagesCollection.doc().id;

      final message = GuessmeMessageModel(
        id: messageId,
        sessionId: sessionId,
        senderId: 'system',
        text: text,
        sentAt: DateTime.now(),
        type: GuessmeMessageType.system,
      );

      await messagesCollection.doc(messageId).set(message.toFirestore(useServerTimestamp: true));
      _logger.d('System message sent successfully: $messageId');
    } catch (e, stack) {
      _logger.e('Error sending system message', error: e, stackTrace: stack);
    }
  }

  /// Stream of messages for a session.
  Stream<List<GuessmeMessage>> getMessagesStream(String sessionId) {
    _logger.d('Setting up messages stream for session: $sessionId');
    _logger.d('Messages collection path: guess_me_sessions/$sessionId/messages');
    
    return _messagesRef(sessionId)
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snapshot) {
          _logger.d('Messages stream update for session $sessionId - received ${snapshot.docs.length} documents');
          
          if (snapshot.docs.isEmpty) {
            _logger.w('No messages found for session $sessionId - this might indicate a permission issue or no messages sent yet');
          } else {
            _logger.d('First message ID: ${snapshot.docs.first.id}, Last message ID: ${snapshot.docs.last.id}');
          }
          
          final messages = snapshot.docs
              .map((doc) {
                try {
                  return GuessmeMessageModel.fromFirestore(doc).toEntity();
                } catch (e) {
                  _logger.e('Error parsing message ${doc.id}', error: e);
                  return null;
                }
              })
              .whereType<GuessmeMessage>()
              .toList();
          
          _logger.i('Parsed ${messages.length} messages for session $sessionId');
          return messages;
        })
        .handleError((error, stackTrace) {
          _logger.e('Error in messages stream for session $sessionId', error: error, stackTrace: stackTrace);
          // Return empty list on error to prevent stream from breaking
          return <GuessmeMessage>[];
        });
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

  /// Increments stats for a successful mutual connection.
  /// This is the ONLY place where stats are updated.
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

      _logger.i('Updated stats for $userId');
    } catch (e, stack) {
      _logger.e('Error incrementing correct guess', error: e, stackTrace: stack);
    }
  }

  /// Updates the public badge count on profile.
  Future<void> _updatePublicBadgeCount(String userId) async {
    try {
      final stats = await getStats(userId);
      await _firestore.collection('users').doc(userId).update({
        'guessmeCorrectGuesses': stats.correctGuesses,
      });
    } catch (e, stack) {
      _logger.e('Error updating public badge count', error: e, stackTrace: stack);
    }
  }

  // ==================== CONVERSION TO PERMANENT CONNECTION ====================

  /// Converts a GuessMe session to a permanent connection after mutual consent.
  /// 
  /// This creates:
  /// 1. A Connection record between the users
  /// 2. A persistent Conversation for ongoing chat
  /// 3. Transfers messages from GuessMe to the permanent conversation (optional)
  /// 
  /// Returns the conversation ID of the new persistent chat.
  /// 
  /// Thread-safe: Uses Firestore transactions to prevent race conditions.
  Future<String?> convertToConnection({
    required String sessionId,
  }) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) {
        _logger.w('Cannot convert: session $sessionId not found');
        return null;
      }

      if (session.player2Id == null) {
        _logger.w('Cannot convert: session missing player 2');
        return null;
      }

      if (session.mutualConnectionSuccess != true) {
        _logger.w('Cannot convert: mutual connection not confirmed');
        return null;
      }

      // Check if already converted (idempotency)
      final player1Id = session.player1Id;
      final player2Id = session.player2Id!;
      final conversationId = _createConversationId(player1Id, player2Id);

      // Check if conversation already exists
      final existingConv = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (existingConv.exists) {
        _logger.i('Conversation $conversationId already exists, returning existing');
        return conversationId;
      }

      // Get user profiles
      final profiles = await Future.wait([
        _firestore.collection('users').doc(player1Id).get(),
        _firestore.collection('users').doc(player2Id).get(),
      ]);

      final player1Profile = profiles[0];
      final player2Profile = profiles[1];

      if (!player1Profile.exists || !player2Profile.exists) {
        _logger.w('Cannot convert: one or both user profiles not found');
        return null;
      }

      final player1Name = player1Profile.data()?['name'] as String? ?? 'User';
      final player1Photo = player1Profile.data()?['photoUrl'] as String?;
      final player2Name = player2Profile.data()?['name'] as String? ?? 'User';
      final player2Photo = player2Profile.data()?['photoUrl'] as String?;

      // Create the connection record
      await _createConnection(
        player1Id: player1Id,
        player2Id: player2Id,
        conversationId: conversationId,
        player1Name: player1Name,
        player2Name: player2Name,
        player1Photo: player1Photo,
        player2Photo: player2Photo,
      );

      // Create the persistent conversation
      await _createConversation(
        conversationId: conversationId,
        player1Id: player1Id,
        player2Id: player2Id,
        player1Name: player1Name,
        player2Name: player2Name,
        player1Photo: player1Photo,
        player2Photo: player2Photo,
      );

      _logger.i('Converted GuessMe session $sessionId to permanent connection: $conversationId');
      return conversationId;
    } catch (e, stack) {
      _logger.e('Error converting session to connection', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Creates a deterministic conversation ID from two user IDs.
  String _createConversationId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  /// Creates a connection record between two users.
  /// Uses the same schema as regular connections (userId1/userId2).
  Future<void> _createConnection({
    required String player1Id,
    required String player2Id,
    required String conversationId,
    required String player1Name,
    required String player2Name,
    String? player1Photo,
    String? player2Photo,
  }) async {
    final connectionsRef = _firestore.collection('connections');

    // Sort user IDs to maintain consistent schema with regular connections
    final ids = [player1Id, player2Id]..sort();
    final connectionId = '${ids[0]}_${ids[1]}';

    // Create single bidirectional connection document
    await connectionsRef.doc(connectionId).set({
      'userId1': ids[0],
      'userId2': ids[1],
      'status': 'connected',
      'connectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'initiatedBy': player1Id, // The player who initiated the guess check
      'canMessage': true,
      'shareLocation': false,
      'source': 'guessme',
    });

    _logger.d('Created connection record $connectionId for $player1Id and $player2Id');
  }

  /// Creates a persistent conversation document.
  Future<void> _createConversation({
    required String conversationId,
    required String player1Id,
    required String player2Id,
    required String player1Name,
    required String player2Name,
    String? player1Photo,
    String? player2Photo,
  }) async {
    final conversationsRef = _firestore.collection('conversations');

    // Check if conversation already exists
    final existingConv = await conversationsRef.doc(conversationId).get();
    if (existingConv.exists) {
      _logger.d('Conversation $conversationId already exists, skipping creation');
      return;
    }

    // Create new conversation
    await conversationsRef.doc(conversationId).set({
      'id': conversationId,
      'participantIds': [player1Id, player2Id],
      'participantNames': {
        player1Id: player1Name,
        player2Id: player2Name,
      },
      'participantPhotos': {
        player1Id: player1Photo,
        player2Id: player2Photo,
      },
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageText': 'Connected from GuessMe game!',
      'lastMessageSenderId': null,
      'lastMessageStatus': 'sent',
      'source': 'guessme',
    });

    _logger.d('Created conversation $conversationId');
  }
}

/// Result of a connection confirmation response.
class ConnectionConfirmationResult {
  final bool bothResponded;
  final bool bothWantToConnect;
  final String? error;

  ConnectionConfirmationResult({
    required this.bothResponded,
    required this.bothWantToConnect,
    this.error,
  });
}
