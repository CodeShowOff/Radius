part of 'discovery_bloc.dart';

/// Base class for discovery events.
sealed class DiscoveryEvent extends Equatable {
  const DiscoveryEvent();

  @override
  List<Object?> get props => [];
}

/// Search for a user by discovery username.
class DiscoverySearchUser extends DiscoveryEvent {
  final String query;

  const DiscoverySearchUser(this.query);

  @override
  List<Object?> get props => [query];
}

/// Clear search results.
class DiscoveryClearSearch extends DiscoveryEvent {
  const DiscoveryClearSearch();
}

/// Send a discovery connection request to another user.
class DiscoverySendRequest extends DiscoveryEvent {
  final String receiverId;
  final String? receiverDisplayName;
  final String? receiverPhotoUrl;
  final String? receiverDiscoveryUsername;
  final String? message;

  const DiscoverySendRequest({
    required this.receiverId,
    this.receiverDisplayName,
    this.receiverPhotoUrl,
    this.receiverDiscoveryUsername,
    this.message,
  });

  @override
  List<Object?> get props => [receiverId, message];
}

/// Load sent and received discovery requests for the current user.
class DiscoveryLoadRequests extends DiscoveryEvent {
  final String userId;
  final String? displayName;
  final String? photoUrl;

  const DiscoveryLoadRequests(
    this.userId, {
    this.displayName,
    this.photoUrl,
  });

  @override
  List<Object?> get props => [userId, displayName, photoUrl];
}

/// Accept a discovery connection request.
class DiscoveryAcceptRequest extends DiscoveryEvent {
  final String requestId;

  const DiscoveryAcceptRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Reject a discovery connection request.
class DiscoveryRejectRequest extends DiscoveryEvent {
  final String requestId;

  const DiscoveryRejectRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Cancel a sent discovery connection request.
class DiscoveryCancelRequest extends DiscoveryEvent {
  final String requestId;

  const DiscoveryCancelRequest(this.requestId);

  @override
  List<Object?> get props => [requestId];
}

/// Validate and set the user's discovery username.
class DiscoverySetUsername extends DiscoveryEvent {
  final String userId;
  final String username;
  final String? oldUsername;

  const DiscoverySetUsername({
    required this.userId,
    required this.username,
    this.oldUsername,
  });

  @override
  List<Object?> get props => [userId, username, oldUsername];
}

/// Check if a discovery username is available.
class DiscoveryCheckUsername extends DiscoveryEvent {
  final String username;
  final String? currentUserId;

  const DiscoveryCheckUsername(this.username, {this.currentUserId});

  @override
  List<Object?> get props => [username, currentUserId];
}

/// Reset discovery state and cancel all active Firestore streams.
/// Used during sign-out to prevent PERMISSION_DENIED errors.
class DiscoveryReset extends DiscoveryEvent {
  const DiscoveryReset();
}

/// Internal: received requests updated from stream.
class _DiscoveryReceivedRequestsUpdated extends DiscoveryEvent {
  final List<ConnectionRequest> requests;

  const _DiscoveryReceivedRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}

/// Internal: sent requests updated from stream.
class _DiscoverySentRequestsUpdated extends DiscoveryEvent {
  final List<ConnectionRequest> requests;

  const _DiscoverySentRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}
