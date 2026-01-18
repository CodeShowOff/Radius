part of 'chat_bloc.dart';

/// Base class for chat events.
sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

/// Open a chat with a user.
class ChatOpen extends ChatEvent {
  final String conversationId;
  final String currentUserId;
  final String? currentUserName;
  final String? currentUserPhotoUrl;
  final String otherUserId;
  final String? otherUserName;
  final String? otherUserPhotoUrl;

  const ChatOpen({
    required this.conversationId,
    required this.currentUserId,
    this.currentUserName,
    this.currentUserPhotoUrl,
    required this.otherUserId,
    this.otherUserName,
    this.otherUserPhotoUrl,
  });

  @override
  List<Object?> get props => [
        conversationId,
        currentUserId,
      currentUserName,
      currentUserPhotoUrl,
        otherUserId,
        otherUserName,
        otherUserPhotoUrl,
      ];
}

/// Close the chat (cleanup).
class ChatClose extends ChatEvent {
  const ChatClose();
}

/// Send a message.
class ChatSendMessage extends ChatEvent {
  final String text;

  const ChatSendMessage(this.text);

  @override
  List<Object?> get props => [text];
}

/// Send an image message.
class ChatSendImage extends ChatEvent {
  final File file;
  final String? caption;
  final ImageSource source; // camera or gallery

  const ChatSendImage(this.file, {this.caption, required this.source});

  @override
  List<Object?> get props => [file, caption, source];
}

/// Send an audio/voice message.
class ChatSendAudio extends ChatEvent {
  final File file;
  final int duration; // in seconds

  const ChatSendAudio(this.file, {required this.duration});

  @override
  List<Object?> get props => [file, duration];
}

/// Send a document.
class ChatSendDocument extends ChatEvent {
  final File file;
  final String? caption;

  const ChatSendDocument(this.file, {this.caption});

  @override
  List<Object?> get props => [file, caption];
}

/// Send a sticker.
class ChatSendSticker extends ChatEvent {
  final File file;

  const ChatSendSticker(this.file);

  @override
  List<Object?> get props => [file];
}

/// Load more (older) messages.
class ChatLoadMore extends ChatEvent {
  const ChatLoadMore();
}

/// Mark messages as read.
class ChatMarkAsRead extends ChatEvent {
  const ChatMarkAsRead();
}

/// Update typing status.
class ChatSetTyping extends ChatEvent {
  final bool isTyping;

  const ChatSetTyping(this.isTyping);

  @override
  List<Object?> get props => [isTyping];
}

/// Delete a message.
class ChatDeleteMessage extends ChatEvent {
  final String messageId;

  const ChatDeleteMessage(this.messageId);

  @override
  List<Object?> get props => [messageId];
}

/// Clear all messages in the chat.
class ChatClear extends ChatEvent {
  const ChatClear();
}

/// Internal: Messages updated from stream.
class _ChatMessagesUpdated extends ChatEvent {
  final List<Message> messages;

  const _ChatMessagesUpdated(this.messages);

  @override
  List<Object?> get props => [messages];
}

/// Internal: Conversation updated from stream.
class _ChatConversationUpdated extends ChatEvent {
  final Conversation? conversation;

  const _ChatConversationUpdated(this.conversation);

  @override
  List<Object?> get props => [conversation];
}

/// Internal: Typing status updated.
class _ChatTypingUpdated extends ChatEvent {
  final bool isOtherUserTyping;

  const _ChatTypingUpdated(this.isOtherUserTyping);

  @override
  List<Object?> get props => [isOtherUserTyping];
}

/// Internal: Any stream/service error surfaced to the bloc.
class _ChatErrorOccurred extends ChatEvent {
  final String message;

  const _ChatErrorOccurred(this.message);

  @override
  List<Object?> get props => [message];
}
