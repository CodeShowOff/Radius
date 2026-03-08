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

/// Retries sending a failed message.
class RetryRandomGroupMessage extends RandomGroupChatEvent {
  final String localId;

  const RetryRandomGroupMessage(this.localId);

  @override
  List<Object?> get props => [localId];
}

/// Send an image message to the random group.
class SendRandomGroupImage extends RandomGroupChatEvent {
  final File file;
  final String? caption;

  const SendRandomGroupImage(this.file, {this.caption});

  @override
  List<Object?> get props => [file, caption];
}

/// Send an audio/voice message to the random group.
class SendRandomGroupAudio extends RandomGroupChatEvent {
  final File file;
  final int duration;

  const SendRandomGroupAudio(this.file, {required this.duration});

  @override
  List<Object?> get props => [file, duration];
}

/// Send a document to the random group.
class SendRandomGroupDocument extends RandomGroupChatEvent {
  final File file;
  final String? caption;

  const SendRandomGroupDocument(this.file, {this.caption});

  @override
  List<Object?> get props => [file, caption];
}

/// Send a video message to the random group.
class SendRandomGroupVideo extends RandomGroupChatEvent {
  final File file;
  final String? caption;
  final int? duration;

  const SendRandomGroupVideo(this.file, {this.caption, this.duration});

  @override
  List<Object?> get props => [file, caption, duration];
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

/// Internal event: unread info fetched for display.
class _UnreadInfoReceived extends RandomGroupChatEvent {
  final String firstUnreadMessageId;
  final int unreadCount;

  const _UnreadInfoReceived(this.firstUnreadMessageId, this.unreadCount);

  @override
  List<Object?> get props => [firstUnreadMessageId, unreadCount];
}
