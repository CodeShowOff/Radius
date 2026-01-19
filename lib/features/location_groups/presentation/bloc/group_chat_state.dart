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

  const GroupChatState({
    this.status = GroupChatStatus.initial,
    this.groupId,
    this.currentUserId,
    this.currentUserName,
    this.currentUserPhotoUrl,
    this.messages = const [],
    this.hasMore = true,
    this.errorMessage,
  });

  /// Whether the chat is currently loading.
  bool get isLoading => status == GroupChatStatus.loading;

  /// Whether a message is being sent.
  bool get isSending => status == GroupChatStatus.sending;

  /// Whether there's an error.
  bool get hasError => status == GroupChatStatus.error;

  /// Whether the chat is open and ready.
  bool get isReady =>
      status == GroupChatStatus.loaded || status == GroupChatStatus.sending;

  GroupChatState copyWith({
    GroupChatStatus? status,
    String? groupId,
    String? currentUserId,
    String? currentUserName,
    String? currentUserPhotoUrl,
    List<GroupMessage>? messages,
    bool? hasMore,
    String? errorMessage,
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
      ];
}
