part of 'connection_bloc.dart';

/// Status of the connection bloc.
enum ConnectionBlocStatus {
  initial,
  loading,
  loaded,
  error,
}

/// State for the connection bloc.
class ConnectionBlocState extends Equatable {
  /// Current status.
  final ConnectionBlocStatus status;

  /// Current user's ID.
  final String? userId;

  /// List of user's connections.
  final List<Connection> connections;

  /// List of received (pending) requests.
  final List<ConnectionRequest> receivedRequests;

  /// List of sent (pending) requests.
  final List<ConnectionRequest> sentRequests;

  /// Connection states with specific users (cached for UI).
  final Map<String, UserConnectionState> userConnectionStates;

  /// Error message if any.
  final String? errorMessage;

  /// Whether an action is in progress.
  final bool isActionLoading;

  /// ID of the request/connection being processed.
  final String? processingId;

  const ConnectionBlocState({
    this.status = ConnectionBlocStatus.initial,
    this.userId,
    this.connections = const [],
    this.receivedRequests = const [],
    this.sentRequests = const [],
    this.userConnectionStates = const {},
    this.errorMessage,
    this.isActionLoading = false,
    this.processingId,
  });

  /// Number of pending received requests (for badge).
  int get pendingRequestCount => receivedRequests.length;

  /// Gets connection state for a specific user.
  UserConnectionState getStateForUser(String otherUserId) {
    return userConnectionStates[otherUserId] ??
        UserConnectionState.notConnected;
  }

  /// Checks if connected with a user.
  bool isConnectedWith(String userId) {
    return connections.any((c) => c.hasUser(userId));
  }

  /// Gets the connection with a specific user.
  Connection? getConnectionWith(String userId) {
    try {
      return connections.firstWhere((c) => c.hasUser(userId));
    } catch (_) {
      return null;
    }
  }

  /// Gets sent request to a specific user.
  ConnectionRequest? getSentRequestTo(String userId) {
    try {
      return sentRequests.firstWhere((r) => r.receiverId == userId);
    } catch (_) {
      return null;
    }
  }

  /// Gets received request from a specific user.
  ConnectionRequest? getReceivedRequestFrom(String userId) {
    try {
      return receivedRequests.firstWhere((r) => r.senderId == userId);
    } catch (_) {
      return null;
    }
  }

  ConnectionBlocState copyWith({
    ConnectionBlocStatus? status,
    String? userId,
    List<Connection>? connections,
    List<ConnectionRequest>? receivedRequests,
    List<ConnectionRequest>? sentRequests,
    Map<String, UserConnectionState>? userConnectionStates,
    String? errorMessage,
    bool? isActionLoading,
    String? processingId,
  }) {
    return ConnectionBlocState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      connections: connections ?? this.connections,
      receivedRequests: receivedRequests ?? this.receivedRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      userConnectionStates: userConnectionStates ?? this.userConnectionStates,
      errorMessage: errorMessage,
      isActionLoading: isActionLoading ?? this.isActionLoading,
      processingId: processingId,
    );
  }

  @override
  List<Object?> get props => [
        status,
        userId,
        connections,
        receivedRequests,
        sentRequests,
        userConnectionStates,
        errorMessage,
        isActionLoading,
        processingId,
      ];
}
