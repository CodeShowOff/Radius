part of 'chat_bloc.dart';

/// Status of the chat bloc.
enum ChatStatus {
  initial,
  loading,
  loaded,
  loadingMore,
  error,
}

/// State for the chat bloc.
class ChatState extends Equatable {
  /// Current status.
  final ChatStatus status;

  /// Conversation ID.
  final String? conversationId;

  /// Current user ID.
  final String? currentUserId;

  /// Other user ID.
  final String? otherUserId;

  /// Other user's display name.
  final String? otherUserName;

  /// Other user's photo URL.
  final String? otherUserPhotoUrl;

  /// List of messages in chronological order.
  final List<Message> messages;

  /// Conversation metadata.
  final Conversation? conversation;

  /// Whether the other user is typing.
  final bool isOtherUserTyping;

  /// Whether there are more messages to load.
  final bool hasMore;

  /// Error message if any.
  final String? errorMessage;

  /// Pending (optimistic) messages waiting for confirmation.
  final Map<String, Message> pendingMessages;

  const ChatState({
    this.status = ChatStatus.initial,
    this.conversationId,
    this.currentUserId,
    this.otherUserId,
    this.otherUserName,
    this.otherUserPhotoUrl,
    this.messages = const [],
    this.conversation,
    this.isOtherUserTyping = false,
    this.hasMore = true,
    this.errorMessage,
    this.pendingMessages = const {},
  });

  /// Gets all messages including pending ones, merged and deduplicated.
  List<Message> get allMessages {
    // Merge pending messages with confirmed messages
    final Map<String, Message> messageMap = {};

    // Add confirmed messages
    for (final msg in messages) {
      messageMap[msg.id] = msg;
    }

    // Add/update with pending messages (by localId or id)
    for (final pending in pendingMessages.values) {
      // Check if this pending message was confirmed
      final confirmed = messages.any((m) =>
          m.localId == pending.localId ||
          (m.sentAt.difference(pending.sentAt).abs().inSeconds < 2 &&
              m.text == pending.text &&
              m.senderId == pending.senderId));

      if (!confirmed) {
        messageMap[pending.localId ?? pending.id] = pending;
      }
    }

    // Sort by sentAt
    final sorted = messageMap.values.toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    return sorted;
  }

  /// Gets the oldest message timestamp for pagination.
  DateTime? get oldestMessageTime =>
      messages.isNotEmpty ? messages.first.sentAt : null;

  ChatState copyWith({
    ChatStatus? status,
    String? conversationId,
    String? currentUserId,
    String? otherUserId,
    String? otherUserName,
    String? otherUserPhotoUrl,
    List<Message>? messages,
    Conversation? conversation,
    bool? isOtherUserTyping,
    bool? hasMore,
    String? errorMessage,
    Map<String, Message>? pendingMessages,
  }) {
    return ChatState(
      status: status ?? this.status,
      conversationId: conversationId ?? this.conversationId,
      currentUserId: currentUserId ?? this.currentUserId,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserPhotoUrl: otherUserPhotoUrl ?? this.otherUserPhotoUrl,
      messages: messages ?? this.messages,
      conversation: conversation ?? this.conversation,
      isOtherUserTyping: isOtherUserTyping ?? this.isOtherUserTyping,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      pendingMessages: pendingMessages ?? this.pendingMessages,
    );
  }

  @override
  List<Object?> get props => [
        status,
        conversationId,
        currentUserId,
        otherUserId,
        otherUserName,
        otherUserPhotoUrl,
        messages,
        conversation,
        isOtherUserTyping,
        hasMore,
        errorMessage,
        pendingMessages,
      ];
}
