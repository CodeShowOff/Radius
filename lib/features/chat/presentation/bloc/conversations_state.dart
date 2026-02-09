part of 'conversations_bloc.dart';

/// Status for the ConversationsBloc.
enum ConversationsStatus {
  initial,
  loading,
  success,
  error,
}

/// State for the ConversationsBloc.
final class ConversationsState extends Equatable {
  final ConversationsStatus status;
  final String? currentUserId;
  final List<Conversation> conversations;
  final bool showArchived;
  final String? errorMessage;
  final int totalUnreadCount;

  /// The conversation ID of the chat the user is currently viewing.
  /// Used to exclude it from totalUnreadCount so the badge doesn't flash
  /// when messages arrive while the user is reading them.
  final String? activeConversationId;

  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.currentUserId,
    this.conversations = const [],
    this.showArchived = false,
    this.errorMessage,
    this.totalUnreadCount = 0,
    this.activeConversationId,
  });

  ConversationsState copyWith({
    ConversationsStatus? status,
    String? currentUserId,
    List<Conversation>? conversations,
    bool? showArchived,
    String? errorMessage,
    int? totalUnreadCount,
    String? activeConversationId,
    bool clearActiveConversationId = false,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      currentUserId: currentUserId ?? this.currentUserId,
      conversations: conversations ?? this.conversations,
      showArchived: showArchived ?? this.showArchived,
      errorMessage: errorMessage ?? this.errorMessage,
      totalUnreadCount: totalUnreadCount ?? this.totalUnreadCount,
      activeConversationId: clearActiveConversationId
          ? null
          : (activeConversationId ?? this.activeConversationId),
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentUserId,
        conversations,
        showArchived,
        errorMessage,
        totalUnreadCount,
        activeConversationId,
      ];
}
