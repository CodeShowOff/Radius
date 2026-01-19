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

  /// Game completed (time expired or someone left).
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

  /// The other player's display name (revealed after game or when viewing badges).
  final String? otherPlayerName;

  /// Error message (if any).
  final String? errorMessage;

  /// Time remaining in the current session (null if not in a game).
  final Duration? timeRemaining;

  /// Whether this user initiated the guess check (waiting for response).
  final bool isGuessCheckInitiator;

  const GuessmeState({
    this.status = GuessmeStatus.initial,
    this.currentUserId,
    this.session,
    this.messages = const [],
    this.stats,
    this.otherPlayerName,
    this.errorMessage,
    this.timeRemaining,
    this.isGuessCheckInitiator = false,
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
    Duration? timeRemaining,
    bool clearTimeRemaining = false,
    bool? isGuessCheckInitiator,
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
      timeRemaining:
          clearTimeRemaining ? null : (timeRemaining ?? this.timeRemaining),
      isGuessCheckInitiator:
          isGuessCheckInitiator ?? this.isGuessCheckInitiator,
    );
  }

  /// Whether the user is in an active game.
  bool get isInGame =>
      status == GuessmeStatus.inGame ||
      status == GuessmeStatus.awaitingGuessResponse ||
      status == GuessmeStatus.receivedGuessCheck;

  /// The other player's ID in the current session.
  String? get otherPlayerId {
    if (session == null || currentUserId == null) return null;
    return session!.player1Id == currentUserId
        ? session!.player2Id
        : session!.player1Id;
  }

  /// Whether this user has already used their guess in this session.
  /// True if this user correctly guessed the other player.
  bool get hasUsedGuess {
    if (session == null || currentUserId == null) return false;
    // Check if we've initiated a guess check that was resolved
    // If I'm player1 and I guessed player2 correctly, player2Guessed is true
    // If I'm player2 and I guessed player1 correctly, player1Guessed is true
    final weArePlayer1 = session!.player1Id == currentUserId;
    return weArePlayer1 ? session!.player2Guessed : session!.player1Guessed;
  }

  /// Whether the other player has used their guess.
  /// True if the other player correctly guessed us.
  bool get otherPlayerHasUsedGuess {
    if (session == null || currentUserId == null) return false;
    // If I'm player1 and player2 guessed me correctly, player1Guessed is true
    // If I'm player2 and player1 guessed me correctly, player2Guessed is true
    final weArePlayer1 = session!.player1Id == currentUserId;
    return weArePlayer1 ? session!.player1Guessed : session!.player2Guessed;
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
        timeRemaining,
        isGuessCheckInitiator,
      ];
}
