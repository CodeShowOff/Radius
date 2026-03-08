part of 'group_chat_bloc.dart';

/// Base class for group chat events.
sealed class GroupChatEvent extends Equatable {
  const GroupChatEvent();

  @override
  List<Object?> get props => [];
}

/// Opens the group chat and starts listening for messages.
class OpenGroupChat extends GroupChatEvent {
  final String groupId;
  final String currentUserId;
  final String? currentUserName;
  final String? currentUserPhotoUrl;

  const OpenGroupChat({
    required this.groupId,
    required this.currentUserId,
    this.currentUserName,
    this.currentUserPhotoUrl,
  });

  @override
  List<Object?> get props => [groupId, currentUserId, currentUserName, currentUserPhotoUrl];
}

/// Closes the group chat and cancels subscriptions.
class CloseGroupChat extends GroupChatEvent {
  const CloseGroupChat();
}

/// Sends a text message to the group.
class SendGroupMessage extends GroupChatEvent {
  final String text;

  const SendGroupMessage(this.text);

  @override
  List<Object?> get props => [text];
}

/// Send an image message to the group.
class SendGroupImage extends GroupChatEvent {
  final File file;
  final String? caption;

  const SendGroupImage(this.file, {this.caption});

  @override
  List<Object?> get props => [file, caption];
}

/// Send an audio/voice message to the group.
class SendGroupAudio extends GroupChatEvent {
  final File file;
  final int duration;

  const SendGroupAudio(this.file, {required this.duration});

  @override
  List<Object?> get props => [file, duration];
}

/// Send a document to the group.
class SendGroupDocument extends GroupChatEvent {
  final File file;
  final String? caption;

  const SendGroupDocument(this.file, {this.caption});

  @override
  List<Object?> get props => [file, caption];
}

/// Send a video message to the group.
class SendGroupVideo extends GroupChatEvent {
  final File file;
  final String? caption;
  final int? duration;

  const SendGroupVideo(this.file, {this.caption, this.duration});

  @override
  List<Object?> get props => [file, caption, duration];
}

/// Loads more (older) messages for pagination.
class LoadMoreGroupMessages extends GroupChatEvent {
  const LoadMoreGroupMessages();
}

/// Internal event: New messages received from stream.
class _GroupMessagesReceived extends GroupChatEvent {
  final List<GroupMessage> messages;

  const _GroupMessagesReceived(this.messages);

  @override
  List<Object?> get props => [messages];
}

/// Internal event: stream error when watching messages.
class _GroupChatStreamError extends GroupChatEvent {
  final String message;

  const _GroupChatStreamError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Deletes a message (soft delete).
class DeleteGroupMessage extends GroupChatEvent {
  final String messageId;

  const DeleteGroupMessage(this.messageId);

  @override
  List<Object?> get props => [messageId];
}

/// Resyncs the group chat stream (for app resume/network reconnect).
/// This resubscribes to the Firestore stream without resetting state,
/// ensuring messages received while backgrounded are fetched.
class ResyncGroupChat extends GroupChatEvent {
  const ResyncGroupChat();
}

/// Clears all local chat messages immediately (after admin clears chat).
class ClearGroupChatMessages extends GroupChatEvent {
  const ClearGroupChatMessages();
}

/// Retries sending a failed message.
class RetryGroupMessage extends GroupChatEvent {
  final String localId;

  const RetryGroupMessage(this.localId);

  @override
  List<Object?> get props => [localId];
}

/// Internal event: unread info fetched for display.
class _UnreadInfoReceived extends GroupChatEvent {
  final String firstUnreadMessageId;
  final int unreadCount;

  const _UnreadInfoReceived(this.firstUnreadMessageId, this.unreadCount);

  @override
  List<Object?> get props => [firstUnreadMessageId, unreadCount];
}
