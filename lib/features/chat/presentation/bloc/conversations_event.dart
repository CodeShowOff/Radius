part of 'conversations_bloc.dart';

/// Events for the ConversationsBloc.
sealed class ConversationsEvent extends Equatable {
  const ConversationsEvent();

  @override
  List<Object?> get props => [];
}

/// Load conversations for a user.
final class ConversationsLoad extends ConversationsEvent {
  final String userId;

  const ConversationsLoad({required this.userId});

  @override
  List<Object?> get props => [userId];
}

/// Refresh the conversations list.
final class ConversationsRefresh extends ConversationsEvent {
  const ConversationsRefresh();
}

/// Mark a conversation as read.
final class ConversationsMarkAsRead extends ConversationsEvent {
  final String conversationId;

  const ConversationsMarkAsRead({required this.conversationId});

  @override
  List<Object?> get props => [conversationId];
}

/// Archive a conversation.
final class ConversationsArchive extends ConversationsEvent {
  final String conversationId;
  final bool archive;

  const ConversationsArchive({
    required this.conversationId,
    this.archive = true,
  });

  @override
  List<Object?> get props => [conversationId, archive];
}

/// Delete a conversation.
final class ConversationsDelete extends ConversationsEvent {
  final String conversationId;

  const ConversationsDelete({required this.conversationId});

  @override
  List<Object?> get props => [conversationId];
}

/// Toggle mute for a conversation.
final class ConversationsMuteToggle extends ConversationsEvent {
  final String conversationId;
  final bool mute;

  const ConversationsMuteToggle({
    required this.conversationId,
    required this.mute,
  });

  @override
  List<Object?> get props => [conversationId, mute];
}

/// Internal event: Conversations updated from stream.
final class _ConversationsUpdated extends ConversationsEvent {
  final List<Conversation> conversations;

  const _ConversationsUpdated(this.conversations);

  @override
  List<Object?> get props => [conversations];
}
