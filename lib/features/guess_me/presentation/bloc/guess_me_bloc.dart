import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/guess_me_service.dart';
import '../../domain/entities/guess_me_session.dart';
import '../../domain/entities/guess_me_stats.dart';

part 'guess_me_event.dart';
part 'guess_me_state.dart';

/// BLoC for managing GuessMe game state.
/// 
/// Game Flow States:
/// - initial -> loading -> ready: Initial load
/// - ready -> inQueue: User taps "Play Game"
/// - inQueue -> inGame: Match found immediately
/// - inGame -> awaitingGuessResponse: User initiates guess check
/// - inGame -> receivedGuessCheck: Other user initiated guess check
/// - inGame/awaitingGuessResponse/receivedGuessCheck -> awaitingConnectionConfirmation: Correct guess
/// - awaitingConnectionConfirmation -> gameEnded: Both responded (or one declined)
/// - inGame -> gameEnded: Timer expired or user left
class GuessmeBloc extends Bloc<GuessmeEvent, GuessmeState> {
  final GuessmeService _service;
  final Logger _logger = Logger();

  /// Expose service for direct access when needed (e.g., for synchronous Firestore writes)
  GuessmeService get service => _service;

  StreamSubscription<GuessmeSession?>? _sessionSubscription;
  StreamSubscription<List<GuessmeMessage>>? _messagesSubscription;
  StreamSubscription<GuessmeStats>? _statsSubscription;
  StreamSubscription<GuessmeSession?>? _queueMonitorSubscription;
  Timer? _expiryTimer;

  String? _currentUserId;
  String? _currentSessionId;

  GuessmeBloc({required GuessmeService service})
      : _service = service,
        super(const GuessmeState()) {
    on<GuessmeInitialize>(_onInitialize);
    on<GuessmeJoinQueue>(_onJoinQueue);
    on<GuessmeLeaveQueue>(_onLeaveQueue);
    on<GuessmeSendMessage>(_onSendMessage);
    on<GuessmeRetryMessage>(_onRetryMessage);
    on<GuessmeRemoveFailedMessage>(_onRemoveFailedMessage);
    on<GuessmeInitiateGuessCheck>(_onInitiateGuessCheck);
    on<GuessmeRespondToGuessCheck>(_onRespondToGuessCheck);
    on<GuessmeRespondToConnectionPrompt>(_onRespondToConnectionPrompt);
    on<GuessmeLeaveGame>(_onLeaveGame);
    on<_GuessmeSessionUpdated>(_onSessionUpdated);
    on<_GuessmeMessagesUpdated>(_onMessagesUpdated);
    on<_GuessmeStatsUpdated>(_onStatsUpdated);
    on<_GuessmeSessionExpired>(_onSessionExpired);
    on<GuessmeMarkSearching>(_onMarkSearching);
    on<GuessmeClearSearching>(_onClearSearching);
    on<GuessmeEnsureSessionSubscription>(_onEnsureSessionSubscription);
  }

  Future<void> _onInitialize(
    GuessmeInitialize event,
    Emitter<GuessmeState> emit,
  ) async {
    _currentUserId = event.userId;

    emit(state.copyWith(
      status: GuessmeStatus.loading,
      currentUserId: event.userId,
    ));

    // Load initial stats first
    final initialStats = await _service.getStats(event.userId);
    
    // Subscribe to stats stream for updates
    _statsSubscription?.cancel();
    _statsSubscription = _service.getStatsStream(event.userId).listen(
          (stats) {
            if (!isClosed) {
              add(_GuessmeStatsUpdated(stats));
            }
          },
        );

    // Check for existing active session
    final existingSession = await _service.getActiveSession(event.userId);
    if (existingSession != null) {
      _subscribeToSession(existingSession.id);
      
      // Determine correct status based on session state
      final status = _getStatusFromSession(existingSession);
      
      emit(state.copyWith(
        status: status,
        session: existingSession,
        stats: initialStats,
      ));
    } else {
      emit(state.copyWith(
        status: GuessmeStatus.ready,
        stats: initialStats,
      ));
    }
  }

  /// Determine the correct BLoC status from session state.
  GuessmeStatus _getStatusFromSession(GuessmeSession session) {
    _logger.d('Determining status - sessionStatus: ${session.status}, awaitingConn: ${session.awaitingConnectionConfirmations}, guessCheckPending: ${session.guessCheckPending}, initiator: ${session.guessCheckInitiator}, currentUser: $_currentUserId');
    
    if (session.status == GuessmeSessionStatus.completed ||
        session.status == GuessmeSessionStatus.cancelled ||
        session.status == GuessmeSessionStatus.expired) {
      return GuessmeStatus.gameEnded;
    }

    if (session.awaitingConnectionConfirmations) {
      return GuessmeStatus.awaitingConnectionConfirmation;
    }

    if (session.guessCheckPending && session.guessCheckInitiator != null) {
      if (session.guessCheckInitiator == _currentUserId) {
        _logger.d('User is guess check initiator - returning awaitingGuessResponse');
        return GuessmeStatus.awaitingGuessResponse;
      } else {
        _logger.d('User received guess check - returning receivedGuessCheck');
        return GuessmeStatus.receivedGuessCheck;
      }
    }

    return GuessmeStatus.inGame;
  }

  Future<void> _onJoinQueue(
    GuessmeJoinQueue event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null) return;

    // Check if already in a game - prevent re-joining queue
    if (state.status == GuessmeStatus.inGame && state.session != null) {
      _logger.i('Already in game, ignoring joinQueue');
      return;
    }

    emit(state.copyWith(status: GuessmeStatus.inQueue));

    // Start monitoring for session creation BEFORE attempting to match
    // This ensures that if another user creates a session with us, we detect it
    _startQueueMonitoring();

    try {
      final sessionId = await _service.joinQueue(
        userId: _currentUserId!,
        nearbyUserIds: event.nearbyUserIds,
      );

      // CRITICAL: Check if we got matched via queue monitor while joinQueue was executing
      // This handles the race condition where another user creates a session with us
      if (state.status == GuessmeStatus.inGame && state.session != null) {
        _logger.i('Already matched via queue monitor, ignoring joinQueue result');
        return;
      }

      if (sessionId != null) {
        // Matched immediately! (We created the session or found an existing one)
        _subscribeToSession(sessionId);
        final session = await _service.getSession(sessionId);
        emit(state.copyWith(
          status: GuessmeStatus.inGame,
          session: session,
        ));
      } else {
        // No immediate match found - emit inQueueNoMatch so the lobby can retry scanning
        // We're still monitoring via _queueMonitorSubscription for when another user
        // creates a session with us
        _logger.i('No immediate match found, emitting inQueueNoMatch status');
        emit(state.copyWith(status: GuessmeStatus.inQueueNoMatch));
      }
    } catch (e, stack) {
      _logger.e('Error joining queue', error: e, stackTrace: stack);
      _stopQueueMonitoring();
      emit(state.copyWith(
        status: GuessmeStatus.error,
        errorMessage: 'Failed to join game: ${e.toString()}',
      ));
    }
  }

  Future<void> _onLeaveQueue(
    GuessmeLeaveQueue event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null) return;

    await _service.leaveQueue(_currentUserId!);
    _stopQueueMonitoring();
    emit(state.copyWith(status: GuessmeStatus.ready));
  }

  Future<void> _onSendMessage(
    GuessmeSendMessage event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null || _currentSessionId == null) {
      _logger.w('Cannot send message: currentUserId=$_currentUserId, currentSessionId=$_currentSessionId');
      return;
    }

    // Don't send messages if game has ended
    if (state.status == GuessmeStatus.gameEnded) {
      _logger.w('Cannot send message: game has ended');
      return;
    }

    final messageText = event.text.trim();
    if (messageText.isEmpty) return;

    _logger.d('Sending message: ${messageText.substring(0, messageText.length.clamp(0, 20))}... (sessionId: $_currentSessionId, senderId: $_currentUserId)');

    // ========================================================================
    // OPTIMISTIC UI: Show message with 'sending' status while waiting for Firestore
    // ========================================================================
    final localId = 'pending_${DateTime.now().millisecondsSinceEpoch}_${messageText.hashCode}';
    final optimisticMessage = GuessmeMessage(
      id: localId,
      sessionId: _currentSessionId!,
      senderId: _currentUserId!,
      text: messageText,
      sentAt: DateTime.now(),
      localId: localId,
    );

    // Add optimistic message to state
    emit(state.copyWith(
      messages: [...state.messages, optimisticMessage],
    ));

    try {
      await _service.sendMessage(
        sessionId: _currentSessionId!,
        senderId: _currentUserId!,
        text: messageText,
      );
      _logger.d('Message written to Firestore successfully');
      // The stream will deliver the confirmed message with the real ID.
      // The _onMessagesUpdated handler will merge and replace the optimistic message.
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);
      
      // Remove the optimistic message on failure
      final updatedMessages = state.messages.where((m) => m.id != localId).toList();
      
      emit(state.copyWith(
        messages: updatedMessages,
        errorMessage: 'Failed to send message',
      ));
    }
  }

  /// Retries sending a failed message.
  Future<void> _onRetryMessage(
    GuessmeRetryMessage event,
    Emitter<GuessmeState> emit,
  ) async {
    // No longer needed without status tracking
  }

  /// Removes a failed message from the UI.
  void _onRemoveFailedMessage(
    GuessmeRemoveFailedMessage event,
    Emitter<GuessmeState> emit,
  ) {
    final updatedMessages = state.messages.where((m) => m.id != event.localMessageId).toList();
    emit(state.copyWith(messages: updatedMessages));
  }

  Future<void> _onInitiateGuessCheck(
    GuessmeInitiateGuessCheck event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null || _currentSessionId == null) return;

    // Validate we can initiate guess check
    if (state.hasUsedGuess) {
      emit(state.copyWith(
        errorMessage: 'You have already used your guess check',
      ));
      return;
    }

    if (state.status == GuessmeStatus.awaitingGuessResponse) {
      emit(state.copyWith(
        errorMessage: 'Already waiting for guess check response',
      ));
      return;
    }

    if (state.status == GuessmeStatus.awaitingConnectionConfirmation) {
      emit(state.copyWith(
        errorMessage: 'Game is already in connection confirmation phase',
      ));
      return;
    }

    try {
      _logger.i('Initiating guess check - sessionId: $_currentSessionId, userId: $_currentUserId');
      await _service.initiateGuessCheck(_currentSessionId!, _currentUserId!);
      _logger.i('Guess check initiated successfully');
      // State will be updated via session subscription
    } catch (e, stack) {
      _logger.e('Error initiating guess check', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to initiate guess check',
      ));
    }
  }

  Future<void> _onRespondToGuessCheck(
    GuessmeRespondToGuessCheck event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null || _currentSessionId == null) return;

    try {
      _logger.i('Responding to guess check - sessionId: $_currentSessionId, isCorrect: ${event.isCorrect}');
      await _service.respondToGuessCheck(
        sessionId: _currentSessionId!,
        responderId: _currentUserId!,
        isCorrect: event.isCorrect,
      );
      _logger.i('Guess check response sent successfully');
      // State will be updated via session subscription
    } catch (e, stack) {
      _logger.e('Error responding to guess check', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to respond to guess check',
      ));
    }
  }

  Future<void> _onRespondToConnectionPrompt(
    GuessmeRespondToConnectionPrompt event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null || _currentSessionId == null) return;

    try {
      final result = await _service.respondToConnectionPrompt(
        sessionId: _currentSessionId!,
        userId: _currentUserId!,
        wantsToConnect: event.wantsToConnect,
      );

      if (result.error != null) {
        emit(state.copyWith(
          errorMessage: result.error,
        ));
        return;
      }

      // If both responded and both want to connect, convert to permanent connection
      if (result.bothResponded && result.bothWantToConnect) {
        _logger.i('Both users agreed to connect - converting session to permanent connection');
        
        // Convert the session to a permanent connection
        final conversationId = await _service.convertToConnection(
          sessionId: _currentSessionId!,
        );

        if (conversationId != null) {
          emit(state.copyWith(
            convertedConversationId: conversationId,
          ));
        }
      }

      // State will be updated via session subscription
      // The session listener will handle transitioning to gameEnded
    } catch (e, stack) {
      _logger.e('Error responding to connection prompt', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to respond',
      ));
    }
  }

  Future<void> _onLeaveGame(
    GuessmeLeaveGame event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null || _currentSessionId == null) return;

    try {
      await _service.cancelSession(_currentSessionId!, _currentUserId!);
      await _service.clearUserGameStatus(_currentUserId!);
      _unsubscribeFromSession();
      emit(state.copyWith(
        status: GuessmeStatus.ready,
        clearSession: true,
        messages: [],
      ));
    } catch (e, stack) {
      _logger.e('Error leaving game', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to leave game',
      ));
    }
  }

  void _onSessionUpdated(
    _GuessmeSessionUpdated event,
    Emitter<GuessmeState> emit,
  ) {
    final session = event.session;

    if (session == null) {
      // Session deleted
      _unsubscribeFromSession();
      if (_currentUserId != null) {
        _service.clearUserGameStatus(_currentUserId!);
      }
      emit(state.copyWith(
        status: GuessmeStatus.ready,
        clearSession: true,
        messages: [],
      ));
      return;
    }

    // Log guess check state for debugging
    if (session.guessCheckPending) {
      _logger.i('Session updated with guessCheckPending=true, initiator=${session.guessCheckInitiator}, currentUser=$_currentUserId');
    }

    // Determine status from session
    final newStatus = _getStatusFromSession(session);
    _logger.d('Session updated - guessCheckPending: ${session.guessCheckPending}, initiator: ${session.guessCheckInitiator}, newStatus: $newStatus, previousStatus: ${state.status}');

    // Start expiry timer if not already running and game is active
    if (newStatus == GuessmeStatus.inGame && 
        session.expiresAt != null && 
        _expiryTimer == null) {
      _startExpiryTimer(session.expiresAt!);
    }

    emit(state.copyWith(
      status: newStatus,
      session: session,
    ));
  }

  void _onMessagesUpdated(
    _GuessmeMessagesUpdated event,
    Emitter<GuessmeState> emit,
  ) {
    _logger.d('Stream delivered ${event.messages.length} messages');
    
    final streamMessages = event.messages;
    final currentMessages = state.messages;
    
    // ========================================================================
    // MERGE STRATEGY: Combine stream messages with pending optimistic messages
    // ========================================================================
    
    // 1. Get all pending optimistic messages from current state
    final pendingMessages = currentMessages.where((m) => m.isPending).toList();
    
    // 2. For each pending message, check if it has been confirmed by the stream
    //    A message is considered confirmed if a stream message has the same
    //    senderId, text, and sentAt is within 30 seconds
    final confirmedLocalIds = <String>{};
    
    for (final pending in pendingMessages) {
      final isConfirmed = streamMessages.any((streamMsg) =>
        streamMsg.senderId == pending.senderId &&
        streamMsg.text == pending.text &&
        streamMsg.sentAt.difference(pending.sentAt).abs() < const Duration(seconds: 30)
      );
      
      if (isConfirmed) {
        confirmedLocalIds.add(pending.id);
        _logger.d('Optimistic message ${pending.id} confirmed by stream');
      }
    }
    
    // 3. Keep only pending messages that haven't been confirmed
    final pendingMessagesToKeep = pendingMessages.where((m) =>
      !confirmedLocalIds.contains(m.id)
    ).toList();
    
    // 4. Merge: stream messages + any remaining pending messages (sorted by time)
    final mergedMessages = [...streamMessages, ...pendingMessagesToKeep];
    mergedMessages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    
    emit(state.copyWith(messages: mergedMessages));
  }

  void _onStatsUpdated(
    _GuessmeStatsUpdated event,
    Emitter<GuessmeState> emit,
  ) {
    emit(state.copyWith(stats: event.stats));
  }

  void _onSessionExpired(
    _GuessmeSessionExpired event,
    Emitter<GuessmeState> emit,
  ) {
    if (_currentSessionId != null) {
      _service.expireSession(_currentSessionId!);
    }
    emit(state.copyWith(
      status: GuessmeStatus.gameEnded,
    ));
  }

  void _subscribeToSession(String sessionId) {
    // Idempotency guard: skip if already subscribed to this session
    if (_currentSessionId == sessionId && _messagesSubscription != null) {
      _logger.d('Already subscribed to session $sessionId, skipping re-subscription');
      return;
    }
    
    _currentSessionId = sessionId;
    _stopQueueMonitoring();
    _logger.i('Subscribing to session: $sessionId');
    _logger.i('Will listen to session updates at: guess_me_sessions/$sessionId');
    _logger.i('Will listen to messages at: guess_me_sessions/$sessionId/messages');

    _sessionSubscription?.cancel();
    _sessionSubscription = _service.getSessionStream(sessionId).listen(
          (session) {
            if (!isClosed) {
              _logger.d('Session stream emitted update for $sessionId');
              add(_GuessmeSessionUpdated(session));
            }
          },
          onError: (e, stackTrace) {
            _logger.e('Session stream error for $sessionId', error: e, stackTrace: stackTrace);
          },
          onDone: () {
            _logger.w('Session stream closed for $sessionId');
          },
        );

    _messagesSubscription?.cancel();
    _messagesSubscription = _service.getMessagesStream(sessionId).listen(
          (messages) {
            if (!isClosed) {
              _logger.i('Messages stream emitted ${messages.length} messages for session $sessionId');
              if (messages.isNotEmpty) {
                _logger.d('Latest message: ${messages.last.text.substring(0, messages.last.text.length.clamp(0, 30))}... (from: ${messages.last.senderId})');
              }
              add(_GuessmeMessagesUpdated(messages));
            }
          },
          onError: (e, stackTrace) {
            _logger.e('Messages stream error for session $sessionId', error: e, stackTrace: stackTrace);
            // Attempt to resubscribe on error
            Future.delayed(const Duration(seconds: 2), () {
              if (!isClosed && _currentSessionId == sessionId) {
                _logger.w('Attempting to resubscribe to messages stream after error');
                _messagesSubscription?.cancel();
                _messagesSubscription = _service.getMessagesStream(sessionId).listen(
                  (messages) {
                    if (!isClosed) {
                      add(_GuessmeMessagesUpdated(messages));
                    }
                  },
                );
              }
            });
          },
          onDone: () {
            _logger.w('Messages stream closed for $sessionId');
          },
        );
  }

  void _startQueueMonitoring() {
    if (_currentUserId == null) return;
    
    _queueMonitorSubscription?.cancel();
    _queueMonitorSubscription = _service.getActiveSessionStream(_currentUserId!).listen(
      (session) {
        if (isClosed) return;
        if (session != null) {
          _logger.i('Detected new session ${session.id} while in queue');
          _subscribeToSession(session.id);
          add(_GuessmeSessionUpdated(session));
        }
      },
      onError: (e) {
        _logger.e('Error monitoring queue', error: e);
      },
    );
  }

  void _stopQueueMonitoring() {
    _queueMonitorSubscription?.cancel();
    _queueMonitorSubscription = null;
  }

  void _unsubscribeFromSession() {
    _sessionSubscription?.cancel();
    _sessionSubscription = null;
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _currentSessionId = null;
  }

  void _startExpiryTimer(DateTime expiresAt) {
    _expiryTimer?.cancel();
    final duration = expiresAt.difference(DateTime.now());
    if (duration.isNegative) {
      add(const _GuessmeSessionExpired());
      return;
    }
    _expiryTimer = Timer(duration, () {
      add(const _GuessmeSessionExpired());
    });
  }

  Future<void> _onMarkSearching(
    GuessmeMarkSearching event,
    Emitter<GuessmeState> emit,
  ) async {
    try {
      await _service.setUserSearching(event.userId);
      _logger.d('Marked user ${event.userId} as searching');
    } catch (e) {
      _logger.w('Error marking user as searching', error: e);
    }
  }

  Future<void> _onClearSearching(
    GuessmeClearSearching event,
    Emitter<GuessmeState> emit,
  ) async {
    try {
      await _service.clearUserSearching(event.userId);
      _logger.d('Cleared searching status for user ${event.userId}');
    } catch (e) {
      _logger.w('Error clearing searching status', error: e);
    }
  }

  /// Ensures the BLoC is subscribed to the given session.
  /// Called by the game page to guarantee message streaming even if
  /// the page was opened via deep link or navigation without going through lobby.
  Future<void> _onEnsureSessionSubscription(
    GuessmeEnsureSessionSubscription event,
    Emitter<GuessmeState> emit,
  ) async {
    final sessionId = event.sessionId;
    
    // If already subscribed to this session, the idempotency guard in 
    // _subscribeToSession will prevent duplicate subscriptions
    if (_currentSessionId == sessionId && _messagesSubscription != null) {
      _logger.d('Already subscribed to session $sessionId');
      return;
    }
    
    _logger.i('Ensuring subscription to session $sessionId');
    
    // Fetch session to get its data
    final session = await _service.getSession(sessionId);
    if (session == null) {
      _logger.w('Session $sessionId not found');
      emit(state.copyWith(
        status: GuessmeStatus.error,
        errorMessage: 'Session not found',
      ));
      return;
    }
    
    // Subscribe to the session
    _subscribeToSession(sessionId);
    
    // Update state with session
    final status = _getStatusFromSession(session);
    emit(state.copyWith(
      status: status,
      session: session,
    ));
  }

  @override
  Future<void> close() async {
    // Cleanup: if user is in a game when bloc closes, clean up their status
    if (_currentUserId != null) {
      try {
        await _service.clearUserGameStatus(_currentUserId!);
        // Also clear searching status
        await _service.clearUserSearching(_currentUserId!);
        if (_currentSessionId != null) {
          await _service.cancelSession(_currentSessionId!, _currentUserId!).catchError((e) {
            _logger.w('Error cancelling session on bloc close', error: e);
          });
        }
        await _service.leaveQueue(_currentUserId!);
      } catch (e) {
        _logger.w('Error during bloc cleanup', error: e);
      }
    }
    
    _sessionSubscription?.cancel();
    _messagesSubscription?.cancel();
    _statsSubscription?.cancel();
    _queueMonitorSubscription?.cancel();
    _expiryTimer?.cancel();
    return super.close();
  }
}
