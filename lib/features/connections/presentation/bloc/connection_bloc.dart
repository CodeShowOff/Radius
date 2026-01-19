import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../data/connection_service.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/connection_request.dart';

part 'connection_event.dart';
part 'connection_state.dart';

/// BLoC for managing user connections.
class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionBlocState> {
  final ConnectionService _connectionService;
  final Logger _logger = Logger();

  StreamSubscription<List<Connection>>? _connectionsSubscription;
  StreamSubscription<List<ConnectionRequest>>? _receivedRequestsSubscription;
  StreamSubscription<List<ConnectionRequest>>? _sentRequestsSubscription;

  String? _currentUserId;
  String? _currentUserDisplayName;
  String? _currentUserPhotoUrl;

  ConnectionBloc({required ConnectionService connectionService})
      : _connectionService = connectionService,
        super(const ConnectionBlocState()) {
    on<ConnectionLoadAll>(_onLoadAll);
    on<ConnectionSendRequest>(_onSendRequest);
    on<ConnectionAcceptRequest>(_onAcceptRequest);
    on<ConnectionRejectRequest>(_onRejectRequest);
    on<ConnectionCancelRequest>(_onCancelRequest);
    on<ConnectionRemove>(_onRemove);
    on<ConnectionBlockUser>(_onBlockUser);
    on<ConnectionUnblockUser>(_onUnblockUser);
    on<ConnectionCheckState>(_onCheckState);
    on<_ConnectionsUpdated>(_onConnectionsUpdated);
    on<_ReceivedRequestsUpdated>(_onReceivedRequestsUpdated);
    on<_SentRequestsUpdated>(_onSentRequestsUpdated);
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

  Future<void> _onLoadAll(
    ConnectionLoadAll event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    // If already loading or loaded for the same user, don't reload
    // This prevents redundant loads when navigating between pages
    // NOTE: Streams remain active and continue to emit real-time updates!
    if (state.userId == event.userId && 
        (state.status == ConnectionBlocStatus.loading || 
         state.status == ConnectionBlocStatus.loaded)) {
      _logger.i('Already loaded/loading for user ${event.userId}, skipping reload');
      _logger.i('Real-time streams remain active - new requests/connections will appear automatically');
      // Update display name/photo if changed
      _currentUserDisplayName = event.displayName;
      _currentUserPhotoUrl = event.photoUrl;
      return;
    }

    emit(state.copyWith(
      status: ConnectionBlocStatus.loading,
      userId: event.userId,
    ));

    _currentUserId = event.userId;
    _currentUserDisplayName = event.displayName;
    _currentUserPhotoUrl = event.photoUrl;

    // Cancel existing subscriptions
    await _connectionsSubscription?.cancel();
    await _receivedRequestsSubscription?.cancel();
    await _sentRequestsSubscription?.cancel();

    try {
      // Subscribe to connections stream - updates automatically when connections change
      _connectionsSubscription = _connectionService
          .getConnectionsStream(event.userId)
          .listen(
            (connections) => add(_ConnectionsUpdated(connections)),
            onError: (error) {
              _logger.e('Error in connections stream', error: error);
              // Still emit empty list so UI can show empty state
              add(const _ConnectionsUpdated([]));
            },
          );

      // Subscribe to received requests stream - new requests appear in real-time
      _receivedRequestsSubscription = _connectionService
          .getReceivedRequestsStream(event.userId)
          .listen(
            (requests) => add(_ReceivedRequestsUpdated(requests)),
            onError: (error) {
              _logger.e('Error in received requests stream', error: error);
              // Still emit empty list so UI doesn't get stuck
              add(const _ReceivedRequestsUpdated([]));
            },
          );

      // Subscribe to sent requests stream - track outgoing requests in real-time
      _sentRequestsSubscription = _connectionService
          .getSentRequestsStream(event.userId)
          .listen(
            (requests) => add(_SentRequestsUpdated(requests)),
            onError: (error) {
              _logger.e('Error in sent requests stream', error: error);
              // Still emit empty list so UI doesn't get stuck
              add(const _SentRequestsUpdated([]));
            },
          );

      // Safety timeout: if still loading after 5 seconds, force transition
      Future.delayed(const Duration(seconds: 5), () {
        if (!isClosed && state.status == ConnectionBlocStatus.loading) {
          _logger.w('Stream initialization timeout - forcing loaded state');
          add(const _ConnectionsUpdated([]));
        }
      });

      // Stay in loading state until we receive initial data from streams
      // The stream update handlers will transition to loaded
    } catch (e) {
      _logger.e('Error setting up connection streams', error: e);
      emit(state.copyWith(
        status: ConnectionBlocStatus.error,
        errorMessage: 'Failed to initialize connections. Please try again.',
      ));
    }
  }

  Future<void> _onSendRequest(
    ConnectionSendRequest event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.receiverId,
    ));

    final result = await _connectionService.sendRequest(
      senderId: _currentUserId!,
      receiverId: event.receiverId,
      message: event.message,
      source: event.source,
      senderDisplayName: _currentUserDisplayName,
      senderPhotoUrl: _currentUserPhotoUrl,
      receiverDisplayName: event.receiverDisplayName,
      receiverPhotoUrl: event.receiverPhotoUrl,
    );

    switch (result) {
      case ConnectionSuccess<ConnectionRequest>():
        // Update connection state for this user
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[event.receiverId] = UserConnectionState.requestSent;

        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          userConnectionStates: updatedStates,
        ));

      case ConnectionFailure<ConnectionRequest>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onAcceptRequest(
    ConnectionAcceptRequest event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.requestId,
    ));

    final result = await _connectionService.acceptRequest(
      requestId: event.requestId,
      currentUserId: _currentUserId!,
    );

    switch (result) {
      case ConnectionSuccess<Connection>():
        // Find the request to get sender ID
        final request = state.receivedRequests
            .where((r) => r.id == event.requestId)
            .firstOrNull;

        if (request == null) {
          _logger.w(
              'Request not found for accepted connection: ${event.requestId}');
          emit(state.copyWith(
            isActionLoading: false,
            processingId: null,
          ));
          return;
        }

        // Update connection state for this user
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[request.senderId] = UserConnectionState.connected;

        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          userConnectionStates: updatedStates,
        ));

      case ConnectionFailure<Connection>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onRejectRequest(
    ConnectionRejectRequest event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.requestId,
    ));

    final result = await _connectionService.rejectRequest(
      requestId: event.requestId,
      currentUserId: _currentUserId!,
    );

    switch (result) {
      case ConnectionSuccess<void>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
        ));

      case ConnectionFailure<void>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onCancelRequest(
    ConnectionCancelRequest event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.requestId,
    ));

    final result = await _connectionService.cancelRequest(
      requestId: event.requestId,
      currentUserId: _currentUserId!,
    );

    switch (result) {
      case ConnectionSuccess<void>():
        // Find the request to get receiver ID
        final request = state.sentRequests
            .where((r) => r.id == event.requestId)
            .firstOrNull;

        if (request == null) {
          _logger
              .w('Request not found for cancelled request: ${event.requestId}');
          emit(state.copyWith(
            isActionLoading: false,
            processingId: null,
          ));
          return;
        }

        // Update connection state for this user
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[request.receiverId] = UserConnectionState.notConnected;

        // Optimistically remove from sent requests list
        // The stream will update, but this provides immediate feedback
        final updatedSentRequests =
            state.sentRequests.where((r) => r.id != event.requestId).toList();

        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          userConnectionStates: updatedStates,
          sentRequests: updatedSentRequests,
        ));

      case ConnectionFailure<void>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onRemove(
    ConnectionRemove event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.connectionId,
    ));

    final result = await _connectionService.removeConnection(
      connectionId: event.connectionId,
      currentUserId: _currentUserId!,
    );

    switch (result) {
      case ConnectionSuccess<void>():
        // Find the connection to get other user ID
        final connection = state.connections
            .where((c) => c.id == event.connectionId)
            .firstOrNull;

        if (connection == null) {
          _logger.w('Connection not found for removal: ${event.connectionId}');
          emit(state.copyWith(
            isActionLoading: false,
            processingId: null,
          ));
          return;
        }

        final otherUserId = connection.getOtherUserId(_currentUserId!);

        // Update connection state for this user
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[otherUserId] = UserConnectionState.notConnected;

        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          userConnectionStates: updatedStates,
        ));

      case ConnectionFailure<void>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onBlockUser(
    ConnectionBlockUser event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.userId,
    ));

    final result = await _connectionService.blockUser(
      blockerId: _currentUserId!,
      blockedId: event.userId,
    );

    switch (result) {
      case ConnectionSuccess<void>():
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[event.userId] = UserConnectionState.blocked;

        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          userConnectionStates: updatedStates,
        ));

      case ConnectionFailure<void>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onUnblockUser(
    ConnectionUnblockUser event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    emit(state.copyWith(
      isActionLoading: true,
      processingId: event.userId,
    ));

    final result = await _connectionService.unblockUser(
      blockerId: _currentUserId!,
      blockedId: event.userId,
    );

    switch (result) {
      case ConnectionSuccess<void>():
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[event.userId] = UserConnectionState.notConnected;

        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          userConnectionStates: updatedStates,
        ));

      case ConnectionFailure<void>():
        emit(state.copyWith(
          isActionLoading: false,
          processingId: null,
          errorMessage: result.message,
        ));
    }
  }

  Future<void> _onCheckState(
    ConnectionCheckState event,
    Emitter<ConnectionBlocState> emit,
  ) async {
    if (_currentUserId == null) return;

    final connectionState = await _connectionService.getConnectionState(
      currentUserId: _currentUserId!,
      otherUserId: event.otherUserId,
    );

    final updatedStates =
        Map<String, UserConnectionState>.from(state.userConnectionStates);
    updatedStates[event.otherUserId] = connectionState;

    emit(state.copyWith(userConnectionStates: updatedStates));
  }

  void _onConnectionsUpdated(
    _ConnectionsUpdated event,
    Emitter<ConnectionBlocState> emit,
  ) {
    // Transition from loading to loaded when we receive first data
    // After that, this handler processes real-time updates from Firestore
    final newStatus = state.status == ConnectionBlocStatus.loading
        ? ConnectionBlocStatus.loaded
        : state.status;
    
    emit(state.copyWith(
      connections: event.connections,
      status: newStatus,
    ));
  }

  void _onReceivedRequestsUpdated(
    _ReceivedRequestsUpdated event,
    Emitter<ConnectionBlocState> emit,
  ) {
    // Transition from loading to loaded when we receive first data
    // New connection requests appear here automatically via Firestore listener
    final newStatus = state.status == ConnectionBlocStatus.loading
        ? ConnectionBlocStatus.loaded
        : state.status;
    
    emit(state.copyWith(
      receivedRequests: event.requests,
      status: newStatus,
    ));
  }

  void _onSentRequestsUpdated(
    _SentRequestsUpdated event,
    Emitter<ConnectionBlocState> emit,
  ) {
    // Transition from loading to loaded when we receive first data
    // Outgoing request status updates appear here in real-time
    final newStatus = state.status == ConnectionBlocStatus.loading
        ? ConnectionBlocStatus.loaded
        : state.status;
    
    emit(state.copyWith(
      sentRequests: event.requests,
      status: newStatus,
    ));
  }

  @override
  Future<void> close() {
    _connectionsSubscription?.cancel();
    _receivedRequestsSubscription?.cancel();
    _sentRequestsSubscription?.cancel();
    return super.close();
  }
}
