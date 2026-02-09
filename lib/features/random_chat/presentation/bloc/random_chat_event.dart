part of 'random_chat_bloc.dart';

/// Base event for Random Chat feature.
abstract class RandomChatEvent extends Equatable {
  const RandomChatEvent();

  @override
  List<Object?> get props => [];
}

/// Load the Random Chat page data for the current user.
class RandomChatLoadRequested extends RandomChatEvent {
  final String userId;
  final String? userGender;

  const RandomChatLoadRequested({
    required this.userId,
    this.userGender,
  });

  @override
  List<Object?> get props => [userId, userGender];
}

/// Send a chat request to a specific user.
class RandomChatSendRequest extends RandomChatEvent {
  final String receiverId;
  final String receiverDisplayName;
  final String? receiverPhotoUrl;

  const RandomChatSendRequest({
    required this.receiverId,
    required this.receiverDisplayName,
    this.receiverPhotoUrl,
  });

  @override
  List<Object?> get props =>
      [receiverId, receiverDisplayName, receiverPhotoUrl];
}

/// Accept an incoming chat request.
class RandomChatAcceptRequest extends RandomChatEvent {
  final String requestId;

  const RandomChatAcceptRequest({required this.requestId});

  @override
  List<Object?> get props => [requestId];
}

/// Reject an incoming chat request.
class RandomChatRejectRequest extends RandomChatEvent {
  final String requestId;

  const RandomChatRejectRequest({required this.requestId});

  @override
  List<Object?> get props => [requestId];
}

/// Refresh the daily suggestions list.
class RandomChatRefreshSuggestions extends RandomChatEvent {
  const RandomChatRefreshSuggestions();
}

/// Internal event: incoming requests updated from stream.
class _IncomingRequestsUpdated extends RandomChatEvent {
  final List<RandomChatRequest> requests;

  const _IncomingRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}

/// Internal event: sent requests updated from stream.
class _SentRequestsUpdated extends RandomChatEvent {
  final List<RandomChatRequest> requests;

  const _SentRequestsUpdated(this.requests);

  @override
  List<Object?> get props => [requests];
}

/// Internal event: active connection updated from stream.
class _ActiveConnectionUpdated extends RandomChatEvent {
  final RandomChatConnection? connection;

  const _ActiveConnectionUpdated(this.connection);

  @override
  List<Object?> get props => [connection];
}

/// Check if the date has changed (midnight reset).
class RandomChatCheckDateChange extends RandomChatEvent {
  const RandomChatCheckDateChange();
}

/// Reset the Random Chat state (e.g., when switching accounts).
class ResetRandomChatState extends RandomChatEvent {
  const ResetRandomChatState();
}
