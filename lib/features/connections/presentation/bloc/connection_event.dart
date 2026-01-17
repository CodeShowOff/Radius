part of 'connection_bloc.dart';

/// Base class for connection events.
sealed class ConnectionEvent extends Equatable {
  const ConnectionEvent();

  @override
  List<Object?> get props => [];
}

/// Load connections and requests for the current user.
class ConnectionLoadAll extends ConnectionEvent {
  final String userId;
  final String? displayName;
  final String? photoUrl;

  const ConnectionLoadAll(
    this.userId, {
    this.displayName,
    this.photoUrl,
  });

  @override
  List<Object?> get props => [userId, displayName, photoUrl];
}

/// Send a connection request to another user.
class ConnectionSendRequest extends ConnectionEvent {
  final String receiverId;
  final String? message;
  final String? source;
  final String? receiverDisplayName;
  final String? receiverPhotoUrl;

  const ConnectionSendRequest({
    required this.receiverId,
    this.message,
    this.source,
    this.receiverDisplayName,
    this.receiverPhotoUrl,
  });

  @override
  List<Object?> get props => [receiverId, message, source];
}

/// Accept a received connection request.
class ConnectionAcceptRequest extends ConnectionEvent {
  final String requestId;

  const ConnectionAcceptRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Reject a received connection request.
class ConnectionRejectRequest extends ConnectionEvent {
  final String requestId;

  const ConnectionRejectRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Cancel a sent connection request.
class ConnectionCancelRequest extends ConnectionEvent {
  final String requestId;

  const ConnectionCancelRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Remove/unfriend a connection.
class ConnectionRemove extends ConnectionEvent {
  final String connectionId;

  const ConnectionRemove(this.connectionId);

  @override
  List<Object?> get props => [connectionId];
}

/// Block a user.
class ConnectionBlockUser extends ConnectionEvent {
  final String userId;

  const ConnectionBlockUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Unblock a user.
class ConnectionUnblockUser extends ConnectionEvent {
  final String userId;

  const ConnectionUnblockUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Internal: Connections list updated from stream.
class _ConnectionsUpdated extends ConnectionEvent {
  final List<Connection> connections;

  const _ConnectionsUpdated(this.connections);

  @override
  List<Object?> get props => [connections];
}

/// Internal: Received requests updated from stream.
class _ReceivedRequestsUpdated extends ConnectionEvent {
  final List<ConnectionRequest> requests;

  const _ReceivedRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}

/// Internal: Sent requests updated from stream.
class _SentRequestsUpdated extends ConnectionEvent {
  final List<ConnectionRequest> requests;

  const _SentRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}

/// Check connection state with a specific user.
class ConnectionCheckState extends ConnectionEvent {
  final String otherUserId;

  const ConnectionCheckState(this.otherUserId);

  @override
  List<Object?> get props => [otherUserId];
}
