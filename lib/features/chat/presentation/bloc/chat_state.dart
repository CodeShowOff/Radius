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

  /// Number of unread messages at the time the chat was opened.
  /// Frozen at open time so it doesn't inflate as new messages arrive.
  final int unreadCountAtOpen;

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
    this.unreadCountAtOpen = 0,
  });

  /// Gets all messages including pending ones, merged and deduplicated.
  List<Message> get allMessages {
    // Merge pending messages with confirmed messages
    final Map<String, Message> messageMap = {};

    // Add confirmed messages from Firestore first
    for (final msg in messages) {
      messageMap[msg.id] = msg;
    }

    // Add pending messages only if not already confirmed.
    // Uses localId-only matching (v_chat_sdk pattern) — no fuzzy matching.
    for (final pending in pendingMessages.values) {
      final pendingLocalId = pending.localId;
      final alreadyConfirmed = pendingLocalId != null &&
          pendingLocalId.isNotEmpty &&
          messages.any((m) =>
              m.localId != null && m.localId == pendingLocalId);

      if (!alreadyConfirmed) {
        messageMap[pendingLocalId ?? pending.id] = pending;
      }
    }

    // Sort by sentAt descending (newest first) to match the stream ordering
    final sorted = messageMap.values.toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));

    // Dynamic Read Receipts: Upgrade status to 'seen' if the other user has read it
    final otherUserId = this.otherUserId;
    final otherUserLastReadAt = conversation?.lastReadAt[otherUserId];

    if (currentUserId != null && otherUserId != null && otherUserLastReadAt != null) {
      return sorted.map((msg) {
        // Only update status for messages sent by the current user
        if (msg.senderId == currentUserId && msg.status == MessageStatus.sent) {
          // If the message was sent before or at the same time the other user last read the chat
          if (!msg.sentAt.isAfter(otherUserLastReadAt)) {
            return msg.copyWith(status: MessageStatus.seen);
          }
        }
        return msg;
      }).toList();
    }

    return sorted;
  }

  /// Gets the oldest message timestamp for pagination.
  /// Since messages are ordered descending (newest first), the oldest is at the end.
  DateTime? get oldestMessageTime =>
      messages.isNotEmpty ? messages.last.sentAt : null;

  /// Gets messages formatted for the flutter_chat_ui package.
  List<types.Message> get chatUiMessages {
    return allMessages.map((msg) {
      final author = types.User(id: msg.senderId);
      final createdAt = msg.sentAt.millisecondsSinceEpoch;
      final status = _mapStatus(msg.status);
      final id = msg.localId ?? msg.id;

      switch (msg.type) {
        case MessageType.text:
          return types.TextMessage(
            author: author,
            createdAt: createdAt,
            id: id,
            text: msg.text,
            status: status,
          );
        case MessageType.image:
          return types.ImageMessage(
            author: author,
            createdAt: createdAt,
            id: id,
            name: msg.mediaFileName ?? 'image.jpg',
            size: msg.mediaFileSize ?? 0,
            uri: msg.localFilePath ?? msg.mediaUrl ?? '',
            status: status,
          );
        case MessageType.audio:
          return types.AudioMessage(
            author: author,
            createdAt: createdAt,
            id: id,
            duration: Duration(seconds: msg.duration ?? 0),
            name: msg.mediaFileName ?? 'audio.m4a',
            size: msg.mediaFileSize ?? 0,
            uri: msg.localFilePath ?? msg.mediaUrl ?? '',
            status: status,
          );
        case MessageType.video:
          return types.VideoMessage(
            author: author,
            createdAt: createdAt,
            id: id,
            name: msg.mediaFileName ?? 'video.mp4',
            size: msg.mediaFileSize ?? 0,
            uri: msg.localFilePath ?? msg.mediaUrl ?? '',
            status: status,
          );
        case MessageType.document:
          return types.FileMessage(
            author: author,
            createdAt: createdAt,
            id: id,
            name: msg.mediaFileName ?? 'document',
            size: msg.mediaFileSize ?? 0,
            uri: msg.localFilePath ?? msg.mediaUrl ?? '',
            status: status,
          );
        case MessageType.sticker:
          // flutter_chat_ui doesn't have a sticker type by default, map to image or custom
          return types.ImageMessage(
            author: author,
            createdAt: createdAt,
            id: id,
            name: msg.mediaFileName ?? 'sticker.png',
            size: msg.mediaFileSize ?? 0,
            uri: msg.localFilePath ?? msg.mediaUrl ?? '',
            status: status,
          );
      }
    }).toList();
  }

  types.Status _mapStatus(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
      case MessageStatus.sending:
        return types.Status.sending;
      case MessageStatus.sent:
        return types.Status.sent;
      case MessageStatus.delivered:
        return types.Status.delivered;
      case MessageStatus.seen:
        return types.Status.seen;
      case MessageStatus.error:
        return types.Status.error;
    }
  }

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
    int? unreadCountAtOpen,
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
      unreadCountAtOpen: clearFirstUnreadMessageId
          ? 0
          : (unreadCountAtOpen ?? this.unreadCountAtOpen),
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
        unreadCountAtOpen,
      ];
}
