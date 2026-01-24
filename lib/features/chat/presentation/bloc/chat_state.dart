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

  /// ID of the first unread message (for showing unread divider).
  final String? firstUnreadMessageId;

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
    this.firstUnreadMessageId,
  });

  /// Gets all messages including pending ones, merged and deduplicated.
  List<Message> get allMessages {
    // Merge pending messages with confirmed messages
    final Map<String, Message> messageMap = {};

    // Add confirmed messages from Firestore first
    for (final msg in messages) {
      messageMap[msg.id] = msg;
    }

    // Add pending messages only if not already confirmed
    for (final pending in pendingMessages.values) {
      // Check if this pending message already exists in confirmed messages
      final alreadyConfirmed = messages.any((m) {
        // Match by localId
        if (m.localId != null && m.localId == pending.localId) return true;
        
        // Fuzzy match: same sender, same text, within 5 seconds
        return m.senderId == pending.senderId &&
            m.text == pending.text &&
            m.sentAt.difference(pending.sentAt).abs().inSeconds < 5;
      });

      // Only add pending message if it hasn't been confirmed yet
      if (!alreadyConfirmed) {
        messageMap[pending.localId ?? pending.id] = pending;
      }
    }

    // Sort by sentAt descending (newest first) to match the stream ordering
    final sorted = messageMap.values.toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

    return sorted;
  }

  /// Gets the oldest message timestamp for pagination.
  /// Since messages are ordered descending (newest first), the oldest is at the end.
  DateTime? get oldestMessageTime =>
      messages.isNotEmpty ? messages.last.sentAt : null;

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
    String? firstUnreadMessageId,
    bool clearFirstUnreadMessageId = false,
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
      firstUnreadMessageId: clearFirstUnreadMessageId
          ? null
          : (firstUnreadMessageId ?? this.firstUnreadMessageId),
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
        firstUnreadMessageId,
      ];
}
