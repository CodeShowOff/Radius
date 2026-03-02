part of 'random_group_chat_bloc.dart';

/// Possible states for the random group chat bloc.
enum RandomGroupChatStatus {
  /// Initial state, no chat loaded.
  initial,

  /// Loading messages.
  loading,

  /// Messages loaded successfully.
  loaded,

  /// Sending a message.
  sending,

  /// Error occurred.
  error,
}

/// State for the random group chat bloc.
class RandomGroupChatState extends Equatable {
  /// Current status.
  final RandomGroupChatStatus status;

  /// Current group ID (null if chat not open).
  final String? currentGroupId;

  /// Current user ID.
  final String? currentUserId;

  /// Current user's username.
  final String? currentUserUsername;

  /// Current user's display name.
  final String? currentUserName;

  /// Current user's photo URL.
  final String? currentUserPhotoUrl;

  /// List of messages (newest first).
  final List<RandomGroupMessage> messages;

  /// Whether there are more messages to load.
  final bool hasMore;

  /// Whether currently loading more messages.
  final bool isLoadingMore;

  /// Error message if any.
  final String? errorMessage;

  /// Whether membership has been verified for this session.
  /// CRITICAL: Chat access is BLOCKED until this is true.
  /// This prevents showing cached messages before membership is confirmed.
  final bool membershipVerified;

  /// ID of the first unread message (for showing unread divider).
  final String? firstUnreadMessageId;

  /// Number of unread messages at the time chat was opened.
  /// Used to display "X unread messages" in the divider.
  final int unreadCountAtOpen;

  /// Whether a chat clear operation is in progress.
  /// When true, incoming stream messages are ignored to prevent
  /// messages from briefly reappearing during batch soft-delete.
  final bool isClearingChat;

  /// Pending messages not yet confirmed by server. Keyed by localId.
  final Map<String, RandomGroupMessage> pendingMessages;

  const RandomGroupChatState({
    this.status = RandomGroupChatStatus.initial,
    this.currentGroupId,
    this.currentUserId,
    this.currentUserUsername,
    this.currentUserName,
    this.currentUserPhotoUrl,
    this.messages = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.errorMessage,
    this.membershipVerified = false,
    this.firstUnreadMessageId,
    this.unreadCountAtOpen = 0,
    this.isClearingChat = false,
    this.pendingMessages = const {},
  });

  /// Whether the chat is currently loading.
  bool get isLoading => status == RandomGroupChatStatus.loading;

  /// Whether a message is being sent.
  bool get isSending => status == RandomGroupChatStatus.sending;

  /// Whether there's an error.
  bool get hasError => status == RandomGroupChatStatus.error;

  /// Whether the chat is open and ready.
  /// CRITICAL: Requires membershipVerified to be true for access control.
  bool get isReady =>
      membershipVerified &&
      (status == RandomGroupChatStatus.loaded || status == RandomGroupChatStatus.sending);

  /// All messages = confirmed + pending (deduped by localId, newest first).
  List<RandomGroupMessage> get allMessages {
    if (pendingMessages.isEmpty) return messages;
    final confirmedLocalIds = <String>{};
    for (final m in messages) {
      if (m.localId != null) confirmedLocalIds.add(m.localId!);
    }
    final pending = pendingMessages.values
        .where((m) => m.localId == null || !confirmedLocalIds.contains(m.localId))
        .toList();
    final all = [...pending, ...messages];
    all.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return all;
  }

  /// Whether membership check is still pending.
  bool get isVerifyingMembership =>
      !membershipVerified && status == RandomGroupChatStatus.loading;

  RandomGroupChatState copyWith({
    RandomGroupChatStatus? status,
    String? currentGroupId,
    String? currentUserId,
    String? currentUserUsername,
    String? currentUserName,
    String? currentUserPhotoUrl,
    List<RandomGroupMessage>? messages,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
    bool clearGroupId = false,
    bool? membershipVerified,
    String? firstUnreadMessageId,
    bool clearFirstUnreadMessageId = false,
    int? unreadCountAtOpen,
    bool? isClearingChat,
    Map<String, RandomGroupMessage>? pendingMessages,
  }) {
    return RandomGroupChatState(
      status: status ?? this.status,
      currentGroupId:
          clearGroupId ? null : (currentGroupId ?? this.currentGroupId),
      currentUserId: currentUserId ?? this.currentUserId,
      currentUserUsername: currentUserUsername ?? this.currentUserUsername,
      currentUserName: currentUserName ?? this.currentUserName,
      currentUserPhotoUrl: currentUserPhotoUrl ?? this.currentUserPhotoUrl,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      membershipVerified: membershipVerified ?? this.membershipVerified,
      firstUnreadMessageId: clearFirstUnreadMessageId
          ? null
          : (firstUnreadMessageId ?? this.firstUnreadMessageId),
      unreadCountAtOpen: unreadCountAtOpen ?? this.unreadCountAtOpen,
      isClearingChat: isClearingChat ?? this.isClearingChat,
      pendingMessages: pendingMessages ?? this.pendingMessages,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentGroupId,
        currentUserId,
        currentUserUsername,
        currentUserName,
        currentUserPhotoUrl,
        messages,
        hasMore,
        isLoadingMore,
        errorMessage,
        membershipVerified,
        firstUnreadMessageId,
        unreadCountAtOpen,
        isClearingChat,
        pendingMessages,
      ];
}
