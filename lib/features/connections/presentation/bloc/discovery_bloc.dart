import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../../../core/services/firebase/discovery_username_service.dart';
import '../../data/connection_service.dart';
import '../../domain/entities/connection_request.dart';

part 'discovery_event.dart';
part 'discovery_state.dart';

/// BLoC for managing discovery username search, requests, and username setting.
///
/// This BLoC handles:
/// - Searching users by discovery username
/// - Sending/accepting/rejecting/canceling discovery connection requests
/// - Setting the user's own discovery username with uniqueness validation
///
/// Discovery connection requests use `source: 'discovery'` to differentiate
/// from nearby (BLE) connection requests.
class DiscoveryBloc extends Bloc<DiscoveryEvent, DiscoveryState> {
  final DiscoveryUsernameService _discoveryService;
  final ConnectionService _connectionService;
  final Logger _logger = Logger();

  StreamSubscription<List<ConnectionRequest>>? _receivedSubscription;
  StreamSubscription<List<ConnectionRequest>>? _sentSubscription;

  String? _currentUserId;
  String? _currentUserDisplayName;
  String? _currentUserPhotoUrl;

  // Track ongoing request operations to prevent duplicates
  final Set<String> _processingRequests = {};

  DiscoveryBloc({
    required DiscoveryUsernameService discoveryService,
    required ConnectionService connectionService,
  })  : _discoveryService = discoveryService,
        _connectionService = connectionService,
        super(const DiscoveryState()) {
    on<DiscoverySearchUser>(_onSearchUser);
    on<DiscoveryClearSearch>(_onClearSearch);
    on<DiscoverySendRequest>(_onSendRequest);
    on<DiscoveryLoadRequests>(_onLoadRequests);
    on<DiscoveryAcceptRequest>(_onAcceptRequest);
    on<DiscoveryRejectRequest>(_onRejectRequest);
    on<DiscoveryCancelRequest>(_onCancelRequest);
    on<DiscoverySetUsername>(_onSetUsername);
    on<DiscoveryCheckUsername>(_onCheckUsername);
    on<_DiscoveryReceivedRequestsUpdated>(_onReceivedUpdated);
    on<_DiscoverySentRequestsUpdated>(_onSentUpdated);
  }

  /// Sets current user info for request metadata.
  void setCurrentUser({
    required String userId,
    String? displayName,
    String? photoUrl,
  }) {
    _currentUserId = userId;
    _currentUserDisplayName = displayName;
    _currentUserPhotoUrl = photoUrl;
  }

  Future<void> _onSearchUser(
    DiscoverySearchUser event,
    Emitter<DiscoveryState> emit,
  ) async {
    final query = event.query.toLowerCase().trim();
    if (query.isEmpty) {
      emit(state.copyWith(
        status: DiscoveryStatus.loaded,
        searchQuery: '',
        clearSearchResult: true,
        searchResults: const [],
      ));
      return;
    }

    emit(state.copyWith(
      status: DiscoveryStatus.searching,
      searchQuery: query,
    ));

    try {
      // Try exact match first
      final exactResult = await _discoveryService.searchByUsername(query);

      if (exactResult != null) {
        // Don't show self in search results
        if (exactResult['userId'] == _currentUserId) {
          emit(state.copyWith(
            status: DiscoveryStatus.searchNoResult,
            searchQuery: query,
            clearSearchResult: true,
            searchResults: const [],
            errorMessage: "That's your own username",
          ));
          return;
        }

        emit(state.copyWith(
          status: DiscoveryStatus.searchResult,
          searchQuery: query,
          searchResult: exactResult,
          searchResults: [exactResult],
        ));
        return;
      }

      // Fallback to prefix search
      final prefixResults = await _discoveryService.searchByPrefix(query);

      // Filter out self
      final filtered = prefixResults
          .where((r) => r['userId'] != _currentUserId)
          .toList();

      if (filtered.isEmpty) {
        emit(state.copyWith(
          status: DiscoveryStatus.searchNoResult,
          searchQuery: query,
          clearSearchResult: true,
          searchResults: const [],
        ));
      } else {
        emit(state.copyWith(
          status: DiscoveryStatus.searchResult,
          searchQuery: query,
          searchResult: filtered.first,
          searchResults: filtered,
        ));
      }
    } catch (e) {
      _logger.e('Error searching for user', error: e);
      emit(state.copyWith(
        status: DiscoveryStatus.searchError,
        errorMessage: 'Failed to search. Please try again.',
      ));
    }
  }

  void _onClearSearch(
    DiscoveryClearSearch event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      status: state.receivedRequests.isNotEmpty || state.sentRequests.isNotEmpty
          ? DiscoveryStatus.loaded
          : DiscoveryStatus.initial,
      searchQuery: '',
      clearSearchResult: true,
      searchResults: const [],
      clearErrorMessage: true,
      clearSuccessMessage: true,
    ));
  }

  Future<void> _onSendRequest(
    DiscoverySendRequest event,
    Emitter<DiscoveryState> emit,
  ) async {
    if (_currentUserId == null) return;

    // Prevent duplicate
    if (_processingRequests.contains(event.receiverId)) {
      _logger.w('Duplicate discovery request blocked: ${event.receiverId}');
      return;
    }

    _processingRequests.add(event.receiverId);

    try {
      emit(state.copyWith(
        isActionLoading: true,
        processingId: event.receiverId,
        clearErrorMessage: true,
        clearSuccessMessage: true,
      ));

      final result = await _connectionService.sendRequest(
        senderId: _currentUserId!,
        receiverId: event.receiverId,
        message: event.message,
        source: 'discovery',
        senderDisplayName: _currentUserDisplayName,
        senderPhotoUrl: _currentUserPhotoUrl,
        receiverDisplayName: event.receiverDisplayName,
        receiverPhotoUrl: event.receiverPhotoUrl,
      );

      switch (result) {
        case ConnectionSuccess():
          emit(state.copyWith(
            isActionLoading: false,
            successMessage: 'Connection request sent!',
          ));
        case ConnectionFailure(:final message):
          emit(state.copyWith(
            isActionLoading: false,
            errorMessage: message,
          ));
      }
    } catch (e) {
      _logger.e('Error sending discovery request', error: e);
      emit(state.copyWith(
        isActionLoading: false,
        errorMessage: 'Failed to send request. Please try again.',
      ));
    } finally {
      _processingRequests.remove(event.receiverId);
    }
  }

  Future<void> _onLoadRequests(
    DiscoveryLoadRequests event,
    Emitter<DiscoveryState> emit,
  ) async {
    // If already loaded for same user, skip
    if (state.userId == event.userId &&
        state.status != DiscoveryStatus.initial) {
      _currentUserDisplayName = event.displayName;
      _currentUserPhotoUrl = event.photoUrl;
      return;
    }

    _currentUserId = event.userId;
    _currentUserDisplayName = event.displayName;
    _currentUserPhotoUrl = event.photoUrl;

    emit(state.copyWith(
      status: DiscoveryStatus.loading,
      userId: event.userId,
    ));

    // Cancel existing subscriptions
    await _receivedSubscription?.cancel();
    await _sentSubscription?.cancel();

    try {
      // Subscribe to received requests - filter for discovery source
      _receivedSubscription = _connectionService
          .getReceivedRequestsStream(event.userId)
          .map((requests) =>
              requests.where((r) => r.source == 'discovery').toList())
          .listen(
        (requests) {
          if (!isClosed) add(_DiscoveryReceivedRequestsUpdated(requests));
        },
        onError: (error) {
          _logger.e('Error in discovery received stream', error: error);
          if (!isClosed) {
            add(const _DiscoveryReceivedRequestsUpdated([]));
          }
        },
      );

      // Subscribe to sent requests - filter for discovery source
      _sentSubscription = _connectionService
          .getSentRequestsStream(event.userId)
          .map((requests) =>
              requests.where((r) => r.source == 'discovery').toList())
          .listen(
        (requests) {
          if (!isClosed) add(_DiscoverySentRequestsUpdated(requests));
        },
        onError: (error) {
          _logger.e('Error in discovery sent stream', error: error);
          if (!isClosed) {
            add(const _DiscoverySentRequestsUpdated([]));
          }
        },
      );

      // Safety timeout
      Future.delayed(const Duration(seconds: 5), () {
        if (!isClosed && state.status == DiscoveryStatus.loading) {
          _logger.w('Discovery stream timeout - forcing loaded state');
          add(const _DiscoveryReceivedRequestsUpdated([]));
        }
      });
    } catch (e) {
      _logger.e('Error setting up discovery streams', error: e);
      emit(state.copyWith(
        status: DiscoveryStatus.error,
        errorMessage: 'Failed to load discovery requests.',
      ));
    }
  }

  void _onReceivedUpdated(
    _DiscoveryReceivedRequestsUpdated event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      status: state.status == DiscoveryStatus.loading
          ? DiscoveryStatus.loaded
          : state.status,
      receivedRequests: event.requests,
    ));
  }

  void _onSentUpdated(
    _DiscoverySentRequestsUpdated event,
    Emitter<DiscoveryState> emit,
  ) {
    emit(state.copyWith(
      status: state.status == DiscoveryStatus.loading
          ? DiscoveryStatus.loaded
          : state.status,
      sentRequests: event.requests,
    ));
  }

  Future<void> _onAcceptRequest(
    DiscoveryAcceptRequest event,
    Emitter<DiscoveryState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.requestId,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    ));

    try {
      final result = await _connectionService.acceptRequest(
        requestId: event.requestId,
        currentUserId: _currentUserId!,
      );

      switch (result) {
        case ConnectionSuccess():
          emit(state.copyWith(
            isActionLoading: false,
            successMessage: 'Connection accepted!',
          ));
        case ConnectionFailure(:final message):
          emit(state.copyWith(
            isActionLoading: false,
            errorMessage: message,
          ));
      }
    } catch (e) {
      _logger.e('Error accepting discovery request', error: e);
      emit(state.copyWith(
        isActionLoading: false,
        errorMessage: 'Failed to accept request.',
      ));
    }
  }

  Future<void> _onRejectRequest(
    DiscoveryRejectRequest event,
    Emitter<DiscoveryState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.requestId,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    ));

    try {
      final result = await _connectionService.rejectRequest(
        requestId: event.requestId,
        currentUserId: _currentUserId!,
      );

      switch (result) {
        case ConnectionSuccess():
          emit(state.copyWith(
            isActionLoading: false,
            successMessage: 'Request declined.',
          ));
        case ConnectionFailure(:final message):
          emit(state.copyWith(
            isActionLoading: false,
            errorMessage: message,
          ));
      }
    } catch (e) {
      _logger.e('Error rejecting discovery request', error: e);
      emit(state.copyWith(
        isActionLoading: false,
        errorMessage: 'Failed to decline request.',
      ));
    }
  }

  Future<void> _onCancelRequest(
    DiscoveryCancelRequest event,
    Emitter<DiscoveryState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.requestId,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    ));

    try {
      final result = await _connectionService.cancelRequest(
        requestId: event.requestId,
        currentUserId: _currentUserId!,
      );

      switch (result) {
        case ConnectionSuccess():
          emit(state.copyWith(
            isActionLoading: false,
            successMessage: 'Request cancelled.',
          ));
        case ConnectionFailure(:final message):
          emit(state.copyWith(
            isActionLoading: false,
            errorMessage: message,
          ));
      }
    } catch (e) {
      _logger.e('Error cancelling discovery request', error: e);
      emit(state.copyWith(
        isActionLoading: false,
        errorMessage: 'Failed to cancel request.',
      ));
    }
  }

  Future<void> _onSetUsername(
    DiscoverySetUsername event,
    Emitter<DiscoveryState> emit,
  ) async {
    final formatError = _discoveryService.validateFormat(event.username);
    if (formatError != null) {
      emit(state.copyWith(
        usernameCheckStatus: UsernameCheckStatus.invalid,
        usernameError: formatError,
      ));
      return;
    }

    emit(state.copyWith(
      usernameCheckStatus: UsernameCheckStatus.checking,
      clearUsernameError: true,
    ));

    try {
      final success = await _discoveryService.claimUsername(
        userId: event.userId,
        newUsername: event.username,
        oldUsername: event.oldUsername,
      );

      if (success) {
        emit(state.copyWith(
          usernameCheckStatus: UsernameCheckStatus.available,
          successMessage: 'Username set successfully!',
        ));
      } else {
        emit(state.copyWith(
          usernameCheckStatus: UsernameCheckStatus.taken,
          usernameError: 'This username is already taken',
        ));
      }
    } catch (e) {
      _logger.e('Error setting discovery username', error: e);
      emit(state.copyWith(
        usernameCheckStatus: UsernameCheckStatus.invalid,
        usernameError: 'Failed to set username. Please try again.',
      ));
    }
  }

  Future<void> _onCheckUsername(
    DiscoveryCheckUsername event,
    Emitter<DiscoveryState> emit,
  ) async {
    final formatError = _discoveryService.validateFormat(event.username);
    if (formatError != null) {
      emit(state.copyWith(
        usernameCheckStatus: UsernameCheckStatus.invalid,
        usernameError: formatError,
      ));
      return;
    }

    emit(state.copyWith(
      usernameCheckStatus: UsernameCheckStatus.checking,
      clearUsernameError: true,
    ));

    try {
      final available = await _discoveryService.isUsernameAvailable(
        event.username,
        excludeUserId: event.currentUserId,
      );

      if (available) {
        emit(state.copyWith(
          usernameCheckStatus: UsernameCheckStatus.available,
          clearUsernameError: true,
        ));
      } else {
        emit(state.copyWith(
          usernameCheckStatus: UsernameCheckStatus.taken,
          usernameError: 'This username is already taken',
        ));
      }
    } catch (e) {
      _logger.e('Error checking username', error: e);
      emit(state.copyWith(
        usernameCheckStatus: UsernameCheckStatus.invalid,
        usernameError: 'Failed to check username.',
      ));
    }
  }

  @override
  Future<void> close() {
    _receivedSubscription?.cancel();
    _sentSubscription?.cancel();
    return super.close();
  }
}
