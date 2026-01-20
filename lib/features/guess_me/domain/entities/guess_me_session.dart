import 'package:equatable/equatable.dart';

/// Status of a GuessMe game session.
enum GuessmeSessionStatus {
  /// Waiting for another player to join.
  waiting,

  /// Game is active, players are chatting.
  active,

  /// Game completed (guessed correctly or mutual connection decision made).
  completed,

  /// Game was cancelled by a player.
  cancelled,

  /// Game expired after 1 hour.
  expired,
}

/// Represents a GuessMe game session between two anonymous players.
class GuessmeSession extends Equatable {
  /// Unique session ID.
  final String id;

  /// First player's user ID.
  final String player1Id;

  /// First player's display name.
  final String? player1Name;

  /// Second player's user ID (null if waiting for match).
  final String? player2Id;

  /// Second player's display name.
  final String? player2Name;

  /// Current session status.
  final GuessmeSessionStatus status;

  /// When the session was created.
  final DateTime createdAt;

  /// When the game started (both players joined).
  final DateTime? startedAt;

  /// When the session expires (1 hour from start).
  final DateTime? expiresAt;

  /// When the session ended.
  final DateTime? endedAt;

  /// Whether player 1 has been guessed correctly.
  final bool player1Guessed;

  /// Whether player 2 has been guessed correctly.
  final bool player2Guessed;

  /// Player who initiated the guess check (if any).
  final String? guessCheckInitiator;

  /// Whether a guess check is currently pending.
  final bool guessCheckPending;

  /// Whether we're waiting for both players to confirm connection.
  final bool awaitingConnectionConfirmations;

  /// Whether player 1 wants to connect permanently.
  final bool? player1WantsToConnect;

  /// Whether player 2 wants to connect permanently.
  final bool? player2WantsToConnect;

  /// Whether both players agreed to connect.
  final bool? mutualConnectionSuccess;

  const GuessmeSession({
    required this.id,
    required this.player1Id,
    this.player1Name,
    this.player2Id,
    this.player2Name,
    required this.status,
    required this.createdAt,
    this.startedAt,
    this.expiresAt,
    this.endedAt,
    this.player1Guessed = false,
    this.player2Guessed = false,
    this.guessCheckInitiator,
    this.guessCheckPending = false,
    this.awaitingConnectionConfirmations = false,
    this.player1WantsToConnect,
    this.player2WantsToConnect,
    this.mutualConnectionSuccess,
  });

  /// Returns true if the session is still active and not expired.
  bool get isActive =>
      status == GuessmeSessionStatus.active &&
      expiresAt != null &&
      DateTime.now().isBefore(expiresAt!);

  /// Returns the time remaining in the session.
  Duration get timeRemaining {
    if (expiresAt == null) return Duration.zero;
    final remaining = expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Get the other player's ID given current user ID.
  String? getOtherPlayerId(String currentUserId) {
    if (currentUserId == player1Id) return player2Id;
    if (currentUserId == player2Id) return player1Id;
    return null;
  }

  /// Get display name for a player.
  String getPlayerDisplayName(String playerId) {
    if (playerId == player1Id) return player1Name ?? 'Mystery User A';
    if (playerId == player2Id) return player2Name ?? 'Mystery User B';
    return 'Mystery User';
  }

  /// Get the other player's name given current user ID.
  String? getOtherPlayerName(String currentUserId) {
    if (currentUserId == player1Id) return player2Name;
    if (currentUserId == player2Id) return player1Name;
    return null;
  }

  /// Check if a specific player has been guessed.
  bool hasPlayerBeenGuessed(String playerId) {
    if (playerId == player1Id) return player1Guessed;
    if (playerId == player2Id) return player2Guessed;
    return false;
  }

  /// Check if a specific player has responded to the connection prompt.
  bool? getPlayerConnectionResponse(String playerId) {
    if (playerId == player1Id) return player1WantsToConnect;
    if (playerId == player2Id) return player2WantsToConnect;
    return null;
  }

  /// Check if we're waiting for a connection response from a specific player.
  bool isWaitingForPlayerResponse(String playerId) {
    if (!awaitingConnectionConfirmations) return false;
    return getPlayerConnectionResponse(playerId) == null;
  }

  GuessmeSession copyWith({
    String? id,
    String? player1Id,
    String? player1Name,
    String? player2Id,
    String? player2Name,
    GuessmeSessionStatus? status,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? expiresAt,
    DateTime? endedAt,
    bool? player1Guessed,
    bool? player2Guessed,
    String? guessCheckInitiator,
    bool? guessCheckPending,
    bool? awaitingConnectionConfirmations,
    bool? player1WantsToConnect,
    bool? player2WantsToConnect,
    bool? mutualConnectionSuccess,
  }) {
    return GuessmeSession(
      id: id ?? this.id,
      player1Id: player1Id ?? this.player1Id,
      player1Name: player1Name ?? this.player1Name,
      player2Id: player2Id ?? this.player2Id,
      player2Name: player2Name ?? this.player2Name,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      endedAt: endedAt ?? this.endedAt,
      player1Guessed: player1Guessed ?? this.player1Guessed,
      player2Guessed: player2Guessed ?? this.player2Guessed,
      guessCheckInitiator: guessCheckInitiator ?? this.guessCheckInitiator,
      guessCheckPending: guessCheckPending ?? this.guessCheckPending,
      awaitingConnectionConfirmations: awaitingConnectionConfirmations ?? this.awaitingConnectionConfirmations,
      player1WantsToConnect: player1WantsToConnect ?? this.player1WantsToConnect,
      player2WantsToConnect: player2WantsToConnect ?? this.player2WantsToConnect,
      mutualConnectionSuccess: mutualConnectionSuccess ?? this.mutualConnectionSuccess,
    );
  }

  @override
  List<Object?> get props => [
        id,
        player1Id,
        player1Name,
        player2Id,
        player2Name,
        status,
        createdAt,
        startedAt,
        expiresAt,
        endedAt,
        player1Guessed,
        player2Guessed,
        guessCheckInitiator,
        guessCheckPending,
        awaitingConnectionConfirmations,
        player1WantsToConnect,
        player2WantsToConnect,
        mutualConnectionSuccess,
      ];
}

/// Type of GuessMe message.
enum GuessmeMessageType {
  /// Regular chat message.
  chat,

  /// System message (game started, etc.).
  system,

  /// Guess check initiated/result message.
  guessCheck,
}

/// Message in a GuessMe chat.
class GuessmeMessage extends Equatable {
  final String id;
  final String sessionId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final GuessmeMessageType type;

  const GuessmeMessage({
    required this.id,
    required this.sessionId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.type = GuessmeMessageType.chat,
  });

  /// Legacy getter for backwards compatibility.
  bool get isSystemMessage => type == GuessmeMessageType.system;

  @override
  List<Object?> get props => [id, sessionId, senderId, text, sentAt, type];
}
