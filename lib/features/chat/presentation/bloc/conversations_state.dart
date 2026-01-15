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
  final int totalUnreadCount;
  final bool showArchived;
  final String? errorMessage;

  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.currentUserId,
    this.conversations = const [],
    this.totalUnreadCount = 0,
    this.showArchived = false,
    this.errorMessage,
  });

  ConversationsState copyWith({
    ConversationsStatus? status,
    String? currentUserId,
    List<Conversation>? conversations,
    int? totalUnreadCount,
    bool? showArchived,
    String? errorMessage,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      currentUserId: currentUserId ?? this.currentUserId,
      conversations: conversations ?? this.conversations,
      totalUnreadCount: totalUnreadCount ?? this.totalUnreadCount,
      showArchived: showArchived ?? this.showArchived,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentUserId,
        conversations,
        totalUnreadCount,
        showArchived,
        errorMessage,
      ];
}
