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
  });

  /// Whether currently loading
  bool get isLoading =>
      status == NearbyGroupChatStatus.loading ||
      status == NearbyGroupChatStatus.sending;

  /// Whether chat is ready for interaction
  bool get isReady =>
      status == NearbyGroupChatStatus.loaded && membershipVerified;

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
      ];
}
