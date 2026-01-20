part of 'guess_me_bloc.dart';

/// The status of the GuessMe feature.
enum GuessmeStatus {
  /// Initial state before initialization.
  initial,

  /// Loading user data and stats.
  loading,

  /// Ready to join queue or view stats.
  ready,

  /// In the matchmaking queue waiting for a match.
  inQueue,

  /// Matched and in an active game.
  inGame,

  /// Waiting for partner to respond to guess check.
  awaitingGuessResponse,

  /// Partner initiated a guess check, waiting for our response.
  receivedGuessCheck,

  /// Correct guess made, waiting for both players to decide on connection.
  awaitingConnectionConfirmation,

  /// Game completed (time expired, someone left, or connection decision made).
  gameEnded,

  /// Error state.
  error,
}

/// The state for the GuessMe feature.
class GuessmeState extends Equatable {
  /// Current status of the feature.
  final GuessmeStatus status;

  /// The current user's ID.
  final String? currentUserId;

  /// The current active session (if any).
  final GuessmeSession? session;

  /// Messages in the current session.
  final List<GuessmeMessage> messages;

  /// The current user's stats.
  final GuessmeStats? stats;

  /// The other player's display name (revealed after game ends).
  final String? otherPlayerName;

  /// Error message (if any).
  final String? errorMessage;

  const GuessmeState({
    this.status = GuessmeStatus.initial,
    this.currentUserId,
    this.session,
    this.messages = const [],
    this.stats,
    this.otherPlayerName,
    this.errorMessage,
  });

  /// Creates a copy with specified changes.
  GuessmeState copyWith({
    GuessmeStatus? status,
    String? currentUserId,
    GuessmeSession? session,
    bool clearSession = false,
    List<GuessmeMessage>? messages,
    GuessmeStats? stats,
    String? otherPlayerName,
    bool clearOtherPlayerName = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return GuessmeState(
      status: status ?? this.status,
      currentUserId: currentUserId ?? this.currentUserId,
      session: clearSession ? null : (session ?? this.session),
      messages: messages ?? this.messages,
      stats: stats ?? this.stats,
      otherPlayerName: clearOtherPlayerName
          ? null
          : (otherPlayerName ?? this.otherPlayerName),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Whether the user is in an active game.
  bool get isInGame =>
      status == GuessmeStatus.inGame ||
      status == GuessmeStatus.awaitingGuessResponse ||
      status == GuessmeStatus.receivedGuessCheck ||
      status == GuessmeStatus.awaitingConnectionConfirmation;

  /// The other player's ID in the current session.
  String? get otherPlayerId {
    if (session == null || currentUserId == null) return null;
    return session!.player1Id == currentUserId
        ? session!.player2Id
        : session!.player1Id;
  }

  /// Whether this user has already used their guess in this session.
  bool get hasUsedGuess {
    if (session == null || currentUserId == null) return false;
    // If I initiated a guess and it was responded to (correct or not)
    // Check if we've been the initiator and the guess check is no longer pending
    final weArePlayer1 = session!.player1Id == currentUserId;
    // A user has "used" their guess if they guessed the other player correctly
    return weArePlayer1 ? session!.player2Guessed : session!.player1Guessed;
  }

  /// Whether the other player has used their guess (guessed us correctly).
  bool get otherPlayerHasGuessed {
    if (session == null || currentUserId == null) return false;
    final weArePlayer1 = session!.player1Id == currentUserId;
    return weArePlayer1 ? session!.player1Guessed : session!.player2Guessed;
  }

  /// Whether we've responded to the connection prompt.
  bool get hasRespondedToConnectionPrompt {
    if (session == null || currentUserId == null) return false;
    final response = session!.getPlayerConnectionResponse(currentUserId!);
    return response != null;
  }

  /// Our response to the connection prompt (null if not responded yet).
  bool? get connectionPromptResponse {
    if (session == null || currentUserId == null) return null;
    return session!.getPlayerConnectionResponse(currentUserId!);
  }

  /// Whether the game ended with a mutual connection.
  bool get mutualConnectionSuccess {
    return session?.mutualConnectionSuccess ?? false;
  }

  @override
  List<Object?> get props => [
        status,
        currentUserId,
        session,
        messages,
        stats,
        otherPlayerName,
        errorMessage,
      ];
}
