import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/connection_service.dart';
import '../../domain/entities/connection.dart';
import '../../domain/entities/connection_request.dart';

part 'connection_event.dart';
part 'connection_state.dart';

/// BLoC for managing user connections.
class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionBlocState> {
  final ConnectionService _connectionService;

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
    emit(state.copyWith(
      status: ConnectionBlocStatus.loading,
      userId: event.userId,
    ));

    _currentUserId = event.userId;

    // Cancel existing subscriptions
    await _connectionsSubscription?.cancel();
    await _receivedRequestsSubscription?.cancel();
    await _sentRequestsSubscription?.cancel();

    // Subscribe to connections stream
    _connectionsSubscription = _connectionService
        .getConnectionsStream(event.userId)
        .listen((connections) => add(_ConnectionsUpdated(connections)));

    // Subscribe to received requests stream
    _receivedRequestsSubscription = _connectionService
        .getReceivedRequestsStream(event.userId)
        .listen((requests) => add(_ReceivedRequestsUpdated(requests)));

    // Subscribe to sent requests stream
    _sentRequestsSubscription = _connectionService
        .getSentRequestsStream(event.userId)
        .listen((requests) => add(_SentRequestsUpdated(requests)));

    emit(state.copyWith(status: ConnectionBlocStatus.loaded));
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
        final request = state.receivedRequests.firstWhere(
          (r) => r.id == event.requestId,
          orElse: () => throw Exception('Request not found'),
        );

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
        final request = state.sentRequests.firstWhere(
          (r) => r.id == event.requestId,
          orElse: () => throw Exception('Request not found'),
        );

        // Update connection state for this user
        final updatedStates =
            Map<String, UserConnectionState>.from(state.userConnectionStates);
        updatedStates[request.receiverId] = UserConnectionState.notConnected;

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
        final connection = state.connections.firstWhere(
          (c) => c.id == event.connectionId,
          orElse: () => throw Exception('Connection not found'),
        );

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
    emit(state.copyWith(connections: event.connections));
  }

  void _onReceivedRequestsUpdated(
    _ReceivedRequestsUpdated event,
    Emitter<ConnectionBlocState> emit,
  ) {
    emit(state.copyWith(receivedRequests: event.requests));
  }

  void _onSentRequestsUpdated(
    _SentRequestsUpdated event,
    Emitter<ConnectionBlocState> emit,
  ) {
    emit(state.copyWith(sentRequests: event.requests));
  }

  @override
  Future<void> close() {
    _connectionsSubscription?.cancel();
    _receivedRequestsSubscription?.cancel();
    _sentRequestsSubscription?.cancel();
    return super.close();
  }
}
