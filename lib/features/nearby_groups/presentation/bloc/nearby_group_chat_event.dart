part of 'nearby_group_chat_bloc.dart';

/// Events for NearbyGroupChatBloc.
sealed class NearbyGroupChatEvent extends Equatable {
  const NearbyGroupChatEvent();

  @override
  List<Object?> get props => [];
}

/// Open a nearby group chat and start listening to messages.
class OpenNearbyGroupChat extends NearbyGroupChatEvent {
  final String groupId;
  final String currentUserId;
  final String currentUsername;
  final String? currentUserName;
  final String? currentUserPhotoUrl;

  const OpenNearbyGroupChat({
    required this.groupId,
    required this.currentUserId,
    required this.currentUsername,
    this.currentUserName,
    this.currentUserPhotoUrl,
  });

  @override
  List<Object?> get props => [
        groupId,
        currentUserId,
        currentUsername,
        currentUserName,
        currentUserPhotoUrl,
      ];
}

/// Close the chat and stop listening.
class CloseNearbyGroupChat extends NearbyGroupChatEvent {
  const CloseNearbyGroupChat();
}

/// Send a message to the group.
class SendNearbyGroupMessage extends NearbyGroupChatEvent {
  final String text;

  const SendNearbyGroupMessage(this.text);

  @override
  List<Object?> get props => [text];
}

/// Load more (older) messages.
class LoadMoreNearbyGroupMessages extends NearbyGroupChatEvent {
  const LoadMoreNearbyGroupMessages();
}

/// Resync chat (e.g., when app returns from background).
class ResyncNearbyGroupChat extends NearbyGroupChatEvent {
  const ResyncNearbyGroupChat();
}

/// Delete a message.
class DeleteNearbyGroupMessage extends NearbyGroupChatEvent {
  final String messageId;

  const DeleteNearbyGroupMessage(this.messageId);

  @override
  List<Object?> get props => [messageId];
}

/// Retries sending a failed message.
class RetryNearbyGroupMessage extends NearbyGroupChatEvent {
  final String localId;

  const RetryNearbyGroupMessage(this.localId);

  @override
  List<Object?> get props => [localId];
}

/// Internal: Messages received from stream.
class _NearbyGroupMessagesReceived extends NearbyGroupChatEvent {
  final List<NearbyGroupMessage> messages;

  const _NearbyGroupMessagesReceived(this.messages);

  @override
  List<Object?> get props => [messages];
}

/// Internal: Stream error.
class _NearbyGroupChatStreamError extends NearbyGroupChatEvent {
  final String error;

  const _NearbyGroupChatStreamError(this.error);

  @override
  List<Object?> get props => [error];
}
