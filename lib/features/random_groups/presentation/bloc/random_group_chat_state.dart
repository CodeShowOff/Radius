part of 'random_group_chat_bloc.dart';

/// Status of the RandomGroupChatBloc.
enum RandomGroupChatStatus {
  initial,
  loading,
  loaded,
  sending,
  error,
}

/// State for the RandomGroupChatBloc.
class RandomGroupChatState extends Equatable {
  /// Current status of the bloc.
  final RandomGroupChatStatus status;

  /// Currently open group ID.
  final String? currentGroupId;

  /// Messages in the current group (newest first).
  final List<RandomGroupMessage> messages;

  /// Whether there are more messages to load.
  final bool hasMore;

  /// Whether currently loading more messages.
  final bool isLoadingMore;

  /// Whether the current user is a member of the group.
  final bool isMember;

  /// Error message if any.
  final String? errorMessage;

  const RandomGroupChatState({
    this.status = RandomGroupChatStatus.initial,
    this.currentGroupId,
    this.messages = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.isMember = false,
    this.errorMessage,
  });

  /// Creates a copy with updated fields.
  RandomGroupChatState copyWith({
    RandomGroupChatStatus? status,
    String? currentGroupId,
    List<RandomGroupMessage>? messages,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isMember,
    String? errorMessage,
    bool clearError = false,
    bool clearGroupId = false,
  }) {
    return RandomGroupChatState(
      status: status ?? this.status,
      currentGroupId:
          clearGroupId ? null : (currentGroupId ?? this.currentGroupId),
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMember: isMember ?? this.isMember,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentGroupId,
        messages,
        hasMore,
        isLoadingMore,
        isMember,
        errorMessage,
      ];
}
