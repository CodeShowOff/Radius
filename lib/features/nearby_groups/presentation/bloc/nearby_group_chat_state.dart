part of 'nearby_group_chat_bloc.dart';

/// Status of the nearby group chat bloc.
enum NearbyGroupChatStatus {
  initial,
  loading,
  loaded,
  sending,
  error,
}

/// State for NearbyGroupChatBloc.
class NearbyGroupChatState extends Equatable {
  /// Current status
  final NearbyGroupChatStatus status;

  /// Group ID being chatted in
  final String? groupId;

  /// Current user's ID
  final String? currentUserId;

  /// Current user's username
  final String? currentUsername;

  /// Current user's display name
  final String? currentUserName;

  /// Current user's photo URL
  final String? currentUserPhotoUrl;

  /// Messages in the chat (newest first)
  final List<NearbyGroupMessage> messages;

  /// Whether there are more messages to load
  final bool hasMore;

  /// Whether user's membership is verified
  final bool membershipVerified;

  /// Error message if any
  final String? errorMessage;

  /// Pending messages not yet confirmed by server. Keyed by localId.
  final Map<String, NearbyGroupMessage> pendingMessages;

  const NearbyGroupChatState({
    this.status = NearbyGroupChatStatus.initial,
    this.groupId,
    this.currentUserId,
    this.currentUsername,
    this.currentUserName,
    this.currentUserPhotoUrl,
    this.messages = const [],
    this.hasMore = true,
    this.membershipVerified = false,
    this.errorMessage,
    this.pendingMessages = const {},
  });

  /// Whether currently loading
  bool get isLoading => status == NearbyGroupChatStatus.loading;

  /// Whether currently sending a message
  bool get isSending => status == NearbyGroupChatStatus.sending;

  /// Whether we're in the process of verifying membership.
  /// SECURITY: UI should show loading spinner during this state.
  bool get isVerifyingMembership =>
      status == NearbyGroupChatStatus.loading && !membershipVerified;

  /// Whether chat is ready for interaction
  bool get isReady =>
      status == NearbyGroupChatStatus.loaded && membershipVerified;

  /// All messages = confirmed + pending (deduped by localId, newest first).
  List<NearbyGroupMessage> get allMessages {
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

  /// Whether there's an error state
  bool get hasError => status == NearbyGroupChatStatus.error;

  NearbyGroupChatState copyWith({
    NearbyGroupChatStatus? status,
    String? groupId,
    String? currentUserId,
    String? currentUsername,
    String? currentUserName,
    String? currentUserPhotoUrl,
    List<NearbyGroupMessage>? messages,
    bool? hasMore,
    bool? membershipVerified,
    String? errorMessage,
    bool clearError = false,
    Map<String, NearbyGroupMessage>? pendingMessages,
  }) {
    return NearbyGroupChatState(
      status: status ?? this.status,
      groupId: groupId ?? this.groupId,
      currentUserId: currentUserId ?? this.currentUserId,
      currentUsername: currentUsername ?? this.currentUsername,
      currentUserName: currentUserName ?? this.currentUserName,
      currentUserPhotoUrl: currentUserPhotoUrl ?? this.currentUserPhotoUrl,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      membershipVerified: membershipVerified ?? this.membershipVerified,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingMessages: pendingMessages ?? this.pendingMessages,
    );
  }

  @override
  List<Object?> get props => [
        status,
        groupId,
        currentUserId,
        currentUsername,
        currentUserName,
        currentUserPhotoUrl,
        messages,
        hasMore,
        membershipVerified,
        errorMessage,
        pendingMessages,
      ];
}
