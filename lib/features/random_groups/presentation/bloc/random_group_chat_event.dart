part of 'random_group_chat_bloc.dart';

/// Events for the RandomGroupChatBloc.
sealed class RandomGroupChatEvent extends Equatable {
  const RandomGroupChatEvent();

  @override
  List<Object?> get props => [];
}

/// Open a group chat and start streaming messages.
class OpenRandomGroupChat extends RandomGroupChatEvent {
  final String groupId;
  final String userId;

  const OpenRandomGroupChat({
    required this.groupId,
    required this.userId,
  });

  @override
  List<Object?> get props => [groupId, userId];
}

/// Close the current group chat.
class CloseRandomGroupChat extends RandomGroupChatEvent {
  const CloseRandomGroupChat();
}

/// Send a message to the group.
class SendRandomGroupMessage extends RandomGroupChatEvent {
  final String groupId;
  final String senderId;
  final String senderUsername;
  final String? senderName;
  final String? senderPhotoUrl;
  final String text;

  const SendRandomGroupMessage({
    required this.groupId,
    required this.senderId,
    required this.senderUsername,
    this.senderName,
    this.senderPhotoUrl,
    required this.text,
  });

  @override
  List<Object?> get props => [
        groupId,
        senderId,
        senderUsername,
        senderName,
        senderPhotoUrl,
        text,
      ];
}

/// Load older messages (pagination).
class LoadMoreRandomGroupMessages extends RandomGroupChatEvent {
  final String groupId;

  const LoadMoreRandomGroupMessages(this.groupId);

  @override
  List<Object?> get props => [groupId];
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
