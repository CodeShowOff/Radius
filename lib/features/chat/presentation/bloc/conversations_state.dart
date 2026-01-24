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

  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.currentUserId,
    this.conversations = const [],
    this.showArchived = false,
    this.errorMessage,
    this.totalUnreadCount = 0,
  });

  ConversationsState copyWith({
    ConversationsStatus? status,
    String? currentUserId,
    List<Conversation>? conversations,
    bool? showArchived,
    String? errorMessage,
    int? totalUnreadCount,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      currentUserId: currentUserId ?? this.currentUserId,
      conversations: conversations ?? this.conversations,
      showArchived: showArchived ?? this.showArchived,
      errorMessage: errorMessage ?? this.errorMessage,
      totalUnreadCount: totalUnreadCount ?? this.totalUnreadCount,
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
      ];
}
