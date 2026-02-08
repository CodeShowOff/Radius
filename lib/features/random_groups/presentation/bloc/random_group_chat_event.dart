part of 'random_group_chat_bloc.dart';

/// Events for the RandomGroupChatBloc.
sealed class RandomGroupChatEvent extends Equatable {
  const RandomGroupChatEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a group chat and starts streaming messages.
class OpenRandomGroupChat extends RandomGroupChatEvent {
  final String groupId;
  final String userId;
  final String? username;
  final String? userName;
  final String? userPhotoUrl;

  const OpenRandomGroupChat({
    required this.groupId,
    required this.userId,
    this.username,
    this.userName,
    this.userPhotoUrl,
  });

  @override
  List<Object?> get props => [groupId, userId, username, userName, userPhotoUrl];
}

/// Closes the group chat and cancels subscriptions.
class CloseRandomGroupChat extends RandomGroupChatEvent {
  const CloseRandomGroupChat();
}

/// Sends a text message to the group.
class SendRandomGroupMessage extends RandomGroupChatEvent {
  final String text;

  const SendRandomGroupMessage(this.text);

  @override
  List<Object?> get props => [text];
}

/// Loads more (older) messages for pagination.
class LoadMoreRandomGroupMessages extends RandomGroupChatEvent {
  const LoadMoreRandomGroupMessages();
}

/// Resyncs the group chat stream (for app resume/network reconnect).
/// This resubscribes to the Firestore stream without resetting state,
/// ensuring messages received while backgrounded are fetched.
class ResyncRandomGroupChat extends RandomGroupChatEvent {
  const ResyncRandomGroupChat();
}

/// Preloads group chat messages into cache without subscribing to streams.
/// This is triggered on long-press of a group tile to warm the cache
/// before navigation, making the chat open instantly even on cache miss.
class PreloadRandomGroupChat extends RandomGroupChatEvent {
  final String groupId;
  final String userId;

  const PreloadRandomGroupChat({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

/// Deletes a message (soft delete).
class DeleteRandomGroupMessage extends RandomGroupChatEvent {
  final String messageId;

  const DeleteRandomGroupMessage(this.messageId);

  @override
  List<Object?> get props => [messageId];
}

/// Clears all local chat messages immediately (after admin clears chat).
class ClearRandomGroupChatMessages extends RandomGroupChatEvent {
  const ClearRandomGroupChatMessages();
}

// Internal events for stream updates
class _MessagesReceived extends RandomGroupChatEvent {
  final List<RandomGroupMessage> messages;

  const _MessagesReceived(this.messages);

  @override
  List<Object?> get props => [messages];
}

class _ChatStreamError extends RandomGroupChatEvent {
  final String message;

  const _ChatStreamError(this.message);

  @override
  List<Object?> get props => [message];
}
