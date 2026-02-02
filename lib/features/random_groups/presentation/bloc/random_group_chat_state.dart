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
      ];
}
