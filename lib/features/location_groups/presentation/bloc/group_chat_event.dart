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
