import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/random_chat_service.dart';
import '../../domain/entities/random_chat_connection.dart';
import '../../domain/entities/random_chat_request.dart';
import '../../domain/entities/random_chat_user.dart';

part 'random_chat_event.dart';
part 'random_chat_state.dart';

/// BLoC for managing the Random Chat feature.
///
/// Handles daily user discovery, sending/receiving requests,
/// and managing connections with real-time updates.
class RandomChatBloc extends Bloc<RandomChatEvent, RandomChatState> {
  final RandomChatService _service;
  final Logger _logger;

  // Current user info (set externally)
  String _currentUserId = '';
  String _currentUserDisplayName = '';
  String? _currentUserPhotoUrl;
  String? _currentUserGender;

  // Real-time stream subscriptions
  StreamSubscription<List<RandomChatRequest>>? _incomingRequestsSub;
  StreamSubscription<List<RandomChatRequest>>? _sentRequestsSub;
  StreamSubscription<RandomChatConnection?>? _connectionSub;

  // Timer for midnight reset detection
  Timer? _midnightTimer;
  String _loadedDateKey = '';
  String _loadedUserId = '';

  RandomChatBloc({
    required RandomChatService service,
    Logger? logger,
  })  : _service = service,
        _logger = logger ?? Logger(),
        super(const RandomChatInitial()) {
    on<RandomChatLoadRequested>(_onLoadRequested);
    on<RandomChatSendRequest>(_onSendRequest);
    on<RandomChatAcceptRequest>(_onAcceptRequest);
    on<RandomChatRejectRequest>(_onRejectRequest);
    on<RandomChatRefreshSuggestions>(_onRefreshSuggestions);
    on<_IncomingRequestsUpdated>(_onIncomingRequestsUpdated);
    on<_SentRequestsUpdated>(_onSentRequestsUpdated);
    on<_ActiveConnectionUpdated>(_onActiveConnectionUpdated);
    on<RandomChatCheckDateChange>(_onCheckDateChange);
    on<ResetRandomChatState>(_onResetRandomChatState);
  }

  /// Set current user metadata for requests.
  void setCurrentUser({
    required String userId,
    required String displayName,
    String? photoUrl,
    String? gender,
  }) {
    _currentUserId = userId;
    _currentUserDisplayName = displayName;
    _currentUserPhotoUrl = photoUrl;
    _currentUserGender = gender;
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  Future<void> _onLoadRequested(
    RandomChatLoadRequested event,
    Emitter<RandomChatState> emit,
  ) async {
    // Store user info
    _currentUserId = event.userId;
    _currentUserGender = event.userGender;

    // Guard against empty userId (e.g. unauthenticated state)
    if (event.userId.isEmpty) {
      emit(const RandomChatError('User not authenticated'));
      return;
    }

    final dateKey = _todayKey;

    // If already loaded for today for the same user WITH suggestions, skip reload.
    // If suggestions were empty, allow a retry so transient errors self-heal.
    if (state is RandomChatLoaded &&
        _loadedDateKey == dateKey &&
        _loadedUserId == event.userId &&
        (state as RandomChatLoaded).suggestions.isNotEmpty) {
      return;
    }

    emit(const RandomChatLoading());

    try {
      // Fetch daily suggestions
      final suggestions = await _service.getDailySuggestions(
        currentUserId: event.userId,
        currentUserGender: event.userGender,
      );

      // Fetch current incoming requests
      final incomingRequests = await _service.getIncomingRequests(event.userId);

      // Fetch sent requests
      final sentRequests = await _service.getSentRequests(event.userId);

      // Fetch active connection
      final activeConnection = await _service.getActiveConnection(event.userId);

      // Only cache the loaded state if we got suggestions.
      // When empty, leave _loadedDateKey/UserId unset so next visit retries.
      if (suggestions.isNotEmpty) {
        _loadedDateKey = dateKey;
        _loadedUserId = event.userId;
      }

      emit(RandomChatLoaded(
        suggestions: suggestions,
        incomingRequests: incomingRequests
            .where((r) => r.status == RandomChatRequestStatus.pending)
            .toList(),
        sentRequests: sentRequests,
        activeConnection: activeConnection,
        dateKey: dateKey,
        loadedUserId: event.userId,
      ));

      // Start real-time listeners
      _startListeners(event.userId);

      // Set up midnight timer
      _setupMidnightTimer();
    } catch (e, stack) {
      _logger.e('Error loading Random Chat', error: e, stackTrace: stack);
      emit(RandomChatError('Failed to load Random Chat: ${e.toString()}'));
    }
  }

  Future<void> _onSendRequest(
    RandomChatSendRequest event,
    Emitter<RandomChatState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RandomChatLoaded) return;

    // Check date hasn't changed
    if (!_isToday(currentState.dateKey)) {
      add(const RandomChatCheckDateChange());
      return;
    }

    // Mark user as processing (optimistic UI)
    emit(currentState.copyWith(
      processingUserIds: {...currentState.processingUserIds, event.receiverId},
    ));

    final result = await _service.sendRequest(
      senderId: _currentUserId,
      senderDisplayName: _currentUserDisplayName,
      senderPhotoUrl: _currentUserPhotoUrl,
      receiverId: event.receiverId,
      receiverDisplayName: event.receiverDisplayName,
      receiverPhotoUrl: event.receiverPhotoUrl,
    );

    final latestState = state;
    if (latestState is! RandomChatLoaded) return;

    // Remove from processing — use latestState (not pre-await currentState)
    // to avoid losing concurrent processing completions.
    final updatedProcessing = {...latestState.processingUserIds}
      ..remove(event.receiverId);

    switch (result) {
      case RandomChatSuccess<RandomChatRequest>(data: final request):
        emit(latestState.copyWith(
          sentRequests: [...latestState.sentRequests, request],
          processingUserIds: updatedProcessing,
        ));

      case RandomChatFailure<RandomChatRequest>(
          message: final message,
          type: final type
        ):
        _logger.w('Send request failed: $message ($type)');

        // If the receiver hit their daily limit, update suggestion locally
        // so the UI immediately shows 'Limit' instead of a stale 'Request' button.
        var updatedSuggestions = latestState.suggestions;
        if (type == RandomChatErrorType.receiverLimitReached) {
          updatedSuggestions = latestState.suggestions.map((u) {
            if (u.userId == event.receiverId) {
              return u.copyWith(receivedRequestCount: 10);
            }
            return u;
          }).toList();
        }

        emit(RandomChatError(message));
        // Restore loaded state with cleared processing so builder has valid state
        emit(latestState.copyWith(
          processingUserIds: updatedProcessing,
          suggestions: updatedSuggestions,
        ));
    }
  }

  Future<void> _onAcceptRequest(
    RandomChatAcceptRequest event,
    Emitter<RandomChatState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RandomChatLoaded) return;

    if (!_isToday(currentState.dateKey)) {
      add(const RandomChatCheckDateChange());
      return;
    }

    final result = await _service.acceptRequest(
      requestId: event.requestId,
      currentUserId: _currentUserId,
    );

    final latestState = state;
    if (latestState is! RandomChatLoaded) return;

    switch (result) {
      case RandomChatSuccess<RandomChatConnection>(data: final connection):
        // Clear ALL incoming requests — with an active connection,
        // the user can no longer accept any. This also closes the brief
        // window where expired requests may still appear before the
        // Cloud Function runs to expire them server-side.
        emit(latestState.copyWith(
          activeConnection: connection,
          incomingRequests: const [],
        ));

      case RandomChatFailure<RandomChatConnection>(message: final message):
        emit(RandomChatError(message));
        emit(latestState);
    }
  }

  Future<void> _onRejectRequest(
    RandomChatRejectRequest event,
    Emitter<RandomChatState> emit,
  ) async {
    final currentState = state;
    if (currentState is! RandomChatLoaded) return;

    // Check date hasn't changed (same guard as accept/send)
    if (!_isToday(currentState.dateKey)) {
      add(const RandomChatCheckDateChange());
      return;
    }

    final result = await _service.rejectRequest(
      requestId: event.requestId,
      currentUserId: _currentUserId,
    );

    final latestState = state;
    if (latestState is! RandomChatLoaded) return;

    switch (result) {
      case RandomChatSuccess<void>():
        final updatedIncoming = latestState.incomingRequests
            .where((r) => r.id != event.requestId)
            .toList();
        emit(latestState.copyWith(incomingRequests: updatedIncoming));

      case RandomChatFailure<void>(message: final message):
        emit(RandomChatError(message));
        emit(latestState);
    }
  }

  Future<void> _onRefreshSuggestions(
    RandomChatRefreshSuggestions event,
    Emitter<RandomChatState> emit,
  ) async {
    if (_currentUserId.isEmpty) return;

    // Only reload data (incoming requests, connections, stats).
    // Suggestions are pinned for the day in the user's profile and
    // will NOT change — getDailySuggestions() returns the cached list.
    add(RandomChatLoadRequested(
      userId: _currentUserId,
      userGender: _currentUserGender,
    ));
  }

  void _onIncomingRequestsUpdated(
    _IncomingRequestsUpdated event,
    Emitter<RandomChatState> emit,
  ) {
    final currentState = state;
    if (currentState is! RandomChatLoaded) return;

    // If user already has an active connection, ignore incoming request updates.
    // The Cloud Function will expire them server-side shortly. Suppressing
    // stream updates here prevents stale pending requests from briefly
    // re-appearing in the UI after we cleared them on connection detection.
    if (currentState.hasActiveConnection) return;

    emit(currentState.copyWith(incomingRequests: event.requests));
  }

  void _onSentRequestsUpdated(
    _SentRequestsUpdated event,
    Emitter<RandomChatState> emit,
  ) {
    final currentState = state;
    if (currentState is! RandomChatLoaded) return;

    emit(currentState.copyWith(sentRequests: event.requests));
  }

  void _onActiveConnectionUpdated(
    _ActiveConnectionUpdated event,
    Emitter<RandomChatState> emit,
  ) {
    final currentState = state;
    if (currentState is! RandomChatLoaded) return;

    if (event.connection != null) {
      // Clear incoming requests immediately when connection is detected.
      // With an active connection, the user can no longer accept any requests.
      // This closes the brief window where stale pending requests appear
      // before the Cloud Function expires them server-side.
      emit(currentState.copyWith(
        activeConnection: event.connection,
        incomingRequests: const [],
      ));
    } else {
      emit(currentState.copyWith(clearActiveConnection: true));
    }
  }

  void _onCheckDateChange(
    RandomChatCheckDateChange event,
    Emitter<RandomChatState> emit,
  ) {
    final currentState = state;

    if (currentState is RandomChatLoaded && !_isToday(currentState.dateKey)) {
      _logger.i('Midnight reset detected — reloading Random Chat');

      // Cancel streams
      _cancelListeners();
      _loadedDateKey = '';
      _loadedUserId = '';

      // Re-load with fresh data
      add(RandomChatLoadRequested(
        userId: _currentUserId,
        userGender: _currentUserGender,
      ));
    }
  }

  void _onResetRandomChatState(
    ResetRandomChatState event,
    Emitter<RandomChatState> emit,
  ) {
    _logger.i('Resetting Random Chat state (account switch)');
    _cleanupAllSubscriptions();
    _loadedDateKey = '';
    _loadedUserId = '';
    _currentUserId = '';
    _currentUserDisplayName = '';
    _currentUserPhotoUrl = null;
    _currentUserGender = null;
    emit(const RandomChatInitial());
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void _cleanupAllSubscriptions() {
    _cancelListeners();
    _midnightTimer?.cancel();
    _midnightTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Real-time listeners
  // ---------------------------------------------------------------------------

  void _startListeners(String userId) {
    _cancelListeners();

    _incomingRequestsSub = _service.watchIncomingRequests(userId).listen(
          (requests) => add(_IncomingRequestsUpdated(requests)),
          onError: (e) => _logger.w('Incoming requests stream error', error: e),
        );

    _sentRequestsSub = _service.watchSentRequests(userId).listen(
          (requests) => add(_SentRequestsUpdated(requests)),
          onError: (e) => _logger.w('Sent requests stream error', error: e),
        );

    _connectionSub = _service.watchActiveConnection(userId).listen(
          (connection) => add(_ActiveConnectionUpdated(connection)),
          onError: (e) => _logger.w('Connection stream error', error: e),
        );
  }

  void _cancelListeners() {
    _incomingRequestsSub?.cancel();
    _incomingRequestsSub = null;
    _sentRequestsSub?.cancel();
    _sentRequestsSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
  }

  // ---------------------------------------------------------------------------
  // Midnight timer
  // ---------------------------------------------------------------------------

  void _setupMidnightTimer() {
    _midnightTimer?.cancel();

    // Use a periodic timer that checks the date every 60 seconds instead of
    // trying to precisely hit midnight with a one-shot timer.
    // This approach is resilient to:
    // - Local device clock being wrong or drifting
    // - Timezone / DST changes while the app is open
    // - Device sleep/wake cycles that skip the exact midnight moment
    // The check is lightweight (string comparison) so 60s polling is negligible.
    // Note: didChangeAppLifecycleState in the page also checks on app resume,
    // so this periodic timer is a complementary safety net for foreground use.
    _midnightTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final currentState = state;
      if (currentState is RandomChatLoaded && !_isToday(currentState.dateKey)) {
        _cancelListeners();
        add(const RandomChatCheckDateChange());
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get _todayKey {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  bool _isToday(String dateKey) => dateKey == _todayKey;

  @override
  Future<void> close() {
    _cleanupAllSubscriptions();
    return super.close();
  }
}
