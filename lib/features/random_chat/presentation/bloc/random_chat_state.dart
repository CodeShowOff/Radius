part of 'random_chat_bloc.dart';

/// Base state for Random Chat feature.
abstract class RandomChatState extends Equatable {
  const RandomChatState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class RandomChatInitial extends RandomChatState {
  const RandomChatInitial();
}

/// Loading state while fetching data.
class RandomChatLoading extends RandomChatState {
  const RandomChatLoading();
}

/// Main loaded state with all Random Chat data.
class RandomChatLoaded extends RandomChatState {
  final List<RandomChatUser> suggestions;
  final List<RandomChatRequest> incomingRequests;
  final List<RandomChatRequest> sentRequests;
  final RandomChatConnection? activeConnection;
  final String dateKey;
  final String loadedUserId; // Track which user's data is currently loaded
  final Set<String> processingUserIds; // users being sent requests

  const RandomChatLoaded({
    required this.suggestions,
    required this.incomingRequests,
    required this.sentRequests,
    this.activeConnection,
    required this.dateKey,
    required this.loadedUserId,
    this.processingUserIds = const {},
  });

  /// Whether the user already has an active connection today.
  bool get hasActiveConnection => activeConnection != null;

  /// Set of user IDs that already have sent requests.
  Set<String> get sentRequestUserIds =>
      sentRequests.map((r) => r.receiverId).toSet();

  RandomChatLoaded copyWith({
    List<RandomChatUser>? suggestions,
    List<RandomChatRequest>? incomingRequests,
    List<RandomChatRequest>? sentRequests,
    RandomChatConnection? activeConnection,
    bool clearActiveConnection = false,
    String? dateKey,
    String? loadedUserId,
    Set<String>? processingUserIds,
  }) {
    return RandomChatLoaded(
      suggestions: suggestions ?? this.suggestions,
      incomingRequests: incomingRequests ?? this.incomingRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      activeConnection: clearActiveConnection
          ? null
          : (activeConnection ?? this.activeConnection),
      dateKey: dateKey ?? this.dateKey,
      loadedUserId: loadedUserId ?? this.loadedUserId,
      processingUserIds: processingUserIds ?? this.processingUserIds,
    );
  }

  @override
  List<Object?> get props => [
        suggestions,
        incomingRequests,
        sentRequests,
        activeConnection,
        dateKey,
        loadedUserId,
        processingUserIds,
      ];
}

/// Error state.
class RandomChatError extends RandomChatState {
  final String message;

  const RandomChatError(this.message);

  @override
  List<Object?> get props => [message];
}
