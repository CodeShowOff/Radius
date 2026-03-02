part of 'group_chat_bloc.dart';

/// Possible states for the group chat bloc.
enum GroupChatStatus {
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

/// State for the group chat bloc.
class GroupChatState extends Equatable {
  /// Current status.
  final GroupChatStatus status;

  /// Current group ID (null if chat not open).
  final String? groupId;

  /// Current user ID.
  final String? currentUserId;

  /// Current user's display name.
  final String? currentUserName;

  /// Current user's photo URL.
  final String? currentUserPhotoUrl;

  /// List of messages (newest first).
  final List<GroupMessage> messages;

  /// Whether there are more messages to load.
  final bool hasMore;

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

  /// Pending messages not yet confirmed by server. Keyed by localId.
  final Map<String, GroupMessage> pendingMessages;

  const GroupChatState({
    this.status = GroupChatStatus.initial,
    this.groupId,
    this.currentUserId,
    this.currentUserName,
    this.currentUserPhotoUrl,
    this.messages = const [],
    this.hasMore = true,
    this.errorMessage,
    this.membershipVerified = false,
    this.firstUnreadMessageId,
    this.unreadCountAtOpen = 0,
    this.pendingMessages = const {},
  });

  /// Whether the chat is currently loading.
  bool get isLoading => status == GroupChatStatus.loading;

  /// Whether a message is being sent.
  bool get isSending => status == GroupChatStatus.sending;

  /// Whether there's an error.
  bool get hasError => status == GroupChatStatus.error;

  /// Whether the chat is open and ready.
  /// CRITICAL: Requires membershipVerified to be true for access control.
  bool get isReady =>
      membershipVerified &&
      (status == GroupChatStatus.loaded || status == GroupChatStatus.sending);

  /// All messages = confirmed + pending (deduped by localId, newest first).
  List<GroupMessage> get allMessages {
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
      !membershipVerified && status == GroupChatStatus.loading;

  GroupChatState copyWith({
    GroupChatStatus? status,
    String? groupId,
    String? currentUserId,
    String? currentUserName,
    String? currentUserPhotoUrl,
    List<GroupMessage>? messages,
    bool? hasMore,
    String? errorMessage,
    bool? membershipVerified,
    String? firstUnreadMessageId,
    bool clearFirstUnreadMessageId = false,
    int? unreadCountAtOpen,
    Map<String, GroupMessage>? pendingMessages,
  }) {
    return GroupChatState(
      status: status ?? this.status,
      groupId: groupId ?? this.groupId,
      currentUserId: currentUserId ?? this.currentUserId,
      currentUserName: currentUserName ?? this.currentUserName,
      currentUserPhotoUrl: currentUserPhotoUrl ?? this.currentUserPhotoUrl,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      membershipVerified: membershipVerified ?? this.membershipVerified,
      firstUnreadMessageId: clearFirstUnreadMessageId
          ? null
          : (firstUnreadMessageId ?? this.firstUnreadMessageId),
      unreadCountAtOpen: unreadCountAtOpen ?? this.unreadCountAtOpen,
      pendingMessages: pendingMessages ?? this.pendingMessages,
    );
  }

  @override
  List<Object?> get props => [
        status,
        groupId,
        currentUserId,
        currentUserName,
        currentUserPhotoUrl,
        messages,
        hasMore,
        errorMessage,
        membershipVerified,
        firstUnreadMessageId,
        unreadCountAtOpen,
        pendingMessages,
      ];
}
