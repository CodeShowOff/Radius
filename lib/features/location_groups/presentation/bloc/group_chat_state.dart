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

  /// ID of the first unread message for showing the "Unread messages" divider.
  /// This is set when opening a chat and cleared after marking messages as read.
  final String? firstUnreadMessageId;

  /// The timestamp when user last read this group.
  /// Used to determine which messages are unread.
  final DateTime? lastReadAt;

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
    this.lastReadAt,
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

  /// Whether membership check is still pending.
  bool get isVerifyingMembership =>
      !membershipVerified && status == GroupChatStatus.loading;

  /// Whether there are unread messages to show a divider for.
  bool get hasUnreadMessages => firstUnreadMessageId != null;

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
    DateTime? lastReadAt,
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
      lastReadAt: lastReadAt ?? this.lastReadAt,
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
        lastReadAt,
      ];
}
