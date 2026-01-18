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
class GuessmeBloc extends Bloc<GuessmeEvent, GuessmeState> {
  final GuessmeService _service;
  final Logger _logger = Logger();

  StreamSubscription<GuessmeSession?>? _sessionSubscription;
  StreamSubscription<List<GuessmeMessage>>? _messagesSubscription;
  StreamSubscription<GuessmeStats>? _statsSubscription;
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
      emit(state.copyWith(
        status: GuessmeStatus.inGame,
        session: existingSession,
      ));
    } else {
      emit(state.copyWith(status: GuessmeStatus.ready));
    }
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
      }
      // If null, we're in queue waiting for match
      // Session subscription will handle when matched
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
    emit(state.copyWith(status: GuessmeStatus.ready));
  }

  Future<void> _onSendMessage(
    GuessmeSendMessage event,
    Emitter<GuessmeState> emit,
  ) async {
    if (_currentUserId == null || _currentSessionId == null) return;

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

    try {
      await _service.initiateGuessCheck(_currentSessionId!, _currentUserId!);
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
    } catch (e, stack) {
      _logger.e('Error responding to guess check', error: e, stackTrace: stack);
      emit(state.copyWith(
        errorMessage: 'Failed to respond to guess check',
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
      emit(state.copyWith(
        status: GuessmeStatus.ready,
        clearSession: true,
        messages: [],
      ));
      return;
    }

    // Check for status changes
    if (session.status == GuessmeSessionStatus.cancelled ||
        session.status == GuessmeSessionStatus.expired ||
        session.status == GuessmeSessionStatus.completed) {
      emit(state.copyWith(
        status: GuessmeStatus.gameEnded,
        session: session,
      ));
      return;
    }

    // Check for guess check pending
    if (session.guessCheckPending && session.guessCheckInitiator != null) {
      final isInitiator = session.guessCheckInitiator == _currentUserId;
      if (isInitiator) {
        // We initiated the guess check, waiting for response
        emit(state.copyWith(
          status: GuessmeStatus.awaitingGuessResponse,
          session: session,
          isGuessCheckInitiator: true,
        ));
      } else {
        // Other player initiated the guess check, we need to respond
        emit(state.copyWith(
          status: GuessmeStatus.receivedGuessCheck,
          session: session,
          isGuessCheckInitiator: false,
        ));
      }
      return;
    }

    // Start expiry timer if not already running
    if (session.expiresAt != null && _expiryTimer == null) {
      _startExpiryTimer(session.expiresAt!);
    }

    emit(state.copyWith(
      status: GuessmeStatus.inGame,
      session: session,
      isGuessCheckInitiator: false,
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

    _sessionSubscription?.cancel();
    _sessionSubscription = _service.getSessionStream(sessionId).listen(
          (session) => add(_GuessmeSessionUpdated(session)),
        );

    _messagesSubscription?.cancel();
    _messagesSubscription = _service.getMessagesStream(sessionId).listen(
          (messages) => add(_GuessmeMessagesUpdated(messages)),
        );
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
    } else {
      _expiryTimer = Timer(duration, () {
        add(const _GuessmeSessionExpired());
      });
    }
  }

  @override
  Future<void> close() {
    _sessionSubscription?.cancel();
    _messagesSubscription?.cancel();
    _statsSubscription?.cancel();
    _expiryTimer?.cancel();
    return super.close();
  }
}
