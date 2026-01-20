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
    on<GuessmeInitiateGuessCheck>(_onInitiateGuessCheck);
    on<GuessmeRespondToGuessCheck>(_onRespondToGuessCheck);
    on<GuessmeRespondToConnectionPrompt>(_onRespondToConnectionPrompt);
    on<GuessmeLeaveGame>(_onLeaveGame);
    on<_GuessmeSessionUpdated>(_onSessionUpdated);
    on<_GuessmeMessagesUpdated>(_onMessagesUpdated);
    on<_GuessmeStatsUpdated>(_onStatsUpdated);
    on<_GuessmeSessionExpired>(_onSessionExpired);
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

    // Subscribe to stats
    _statsSubscription?.cancel();
    _statsSubscription = _service.getStatsStream(event.userId).listen(
          (stats) => add(_GuessmeStatsUpdated(stats)),
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
      ));
    } else {
      emit(state.copyWith(status: GuessmeStatus.ready));
    }
  }

  /// Determine the correct BLoC status from session state.
  GuessmeStatus _getStatusFromSession(GuessmeSession session) {
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
        return GuessmeStatus.awaitingGuessResponse;
      } else {
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

    emit(state.copyWith(status: GuessmeStatus.inQueue));

    try {
      final sessionId = await _service.joinQueue(
        userId: _currentUserId!,
        nearbyUserIds: event.nearbyUserIds,
      );

      if (sessionId != null) {
        // Matched immediately!
        _subscribeToSession(sessionId);
        final session = await _service.getSession(sessionId);
        emit(state.copyWith(
          status: GuessmeStatus.inGame,
          session: session,
        ));
      } else {
        // No match found, monitoring for match
        _startQueueMonitoring();
      }
    } catch (e, stack) {
      _logger.e('Error joining queue', error: e, stackTrace: stack);
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
    if (_currentUserId == null || _currentSessionId == null) return;

    // Don't send messages if game has ended
    if (state.status == GuessmeStatus.gameEnded) {
      return;
    }

    try {
      await _service.sendMessage(
        sessionId: _currentSessionId!,
        senderId: _currentUserId!,
        text: event.text,
      );
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to send message',
      ));
    }
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
      await _service.initiateGuessCheck(_currentSessionId!, _currentUserId!);
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
      await _service.respondToGuessCheck(
        sessionId: _currentSessionId!,
        responderId: _currentUserId!,
        isCorrect: event.isCorrect,
      );
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

    // Determine status from session
    final newStatus = _getStatusFromSession(session);

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
    emit(state.copyWith(messages: event.messages));
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
    _currentSessionId = sessionId;
    _stopQueueMonitoring();

    _sessionSubscription?.cancel();
    _sessionSubscription = _service.getSessionStream(sessionId).listen(
          (session) => add(_GuessmeSessionUpdated(session)),
        );

    _messagesSubscription?.cancel();
    _messagesSubscription = _service.getMessagesStream(sessionId).listen(
          (messages) => add(_GuessmeMessagesUpdated(messages)),
        );
  }

  void _startQueueMonitoring() {
    if (_currentUserId == null) return;
    
    _queueMonitorSubscription?.cancel();
    _queueMonitorSubscription = _service.getActiveSessionStream(_currentUserId!).listen(
      (session) {
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

  @override
  Future<void> close() async {
    // Cleanup: if user is in a game when bloc closes, clean up their status
    if (_currentUserId != null) {
      try {
        await _service.clearUserGameStatus(_currentUserId!);
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
