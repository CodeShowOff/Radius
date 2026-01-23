part of 'guess_me_bloc.dart';

/// Base class for GuessMe events.
sealed class GuessmeEvent extends Equatable {
  const GuessmeEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the GuessMe feature for a user.
class GuessmeInitialize extends GuessmeEvent {
  final String userId;

  const GuessmeInitialize(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Join the matchmaking queue with nearby users.
class GuessmeJoinQueue extends GuessmeEvent {
  final List<String> nearbyUserIds;

  const GuessmeJoinQueue(this.nearbyUserIds);

  @override
  List<Object?> get props => [nearbyUserIds];
}

/// Leave the matchmaking queue.
class GuessmeLeaveQueue extends GuessmeEvent {
  const GuessmeLeaveQueue();
}

/// Send a chat message.
class GuessmeSendMessage extends GuessmeEvent {
  final String text;

  const GuessmeSendMessage(this.text);

  @override
  List<Object?> get props => [text];
}

/// Retry sending a failed message.
class GuessmeRetryMessage extends GuessmeEvent {
  final String localMessageId;
  final String text;

  const GuessmeRetryMessage({required this.localMessageId, required this.text});

  @override
  List<Object?> get props => [localMessageId, text];
}

/// Remove a failed message from the UI.
class GuessmeRemoveFailedMessage extends GuessmeEvent {
  final String localMessageId;

  const GuessmeRemoveFailedMessage(this.localMessageId);

  @override
  List<Object?> get props => [localMessageId];
}

/// Initiate a guess check (I think I know who you are).
class GuessmeInitiateGuessCheck extends GuessmeEvent {
  const GuessmeInitiateGuessCheck();
}

/// Respond to a guess check from the other player.
class GuessmeRespondToGuessCheck extends GuessmeEvent {
  final bool isCorrect;

  const GuessmeRespondToGuessCheck(this.isCorrect);

  @override
  List<Object?> get props => [isCorrect];
}

/// Respond to the connection prompt after a successful guess.
class GuessmeRespondToConnectionPrompt extends GuessmeEvent {
  final bool wantsToConnect;

  const GuessmeRespondToConnectionPrompt(this.wantsToConnect);

  @override
  List<Object?> get props => [wantsToConnect];
}

/// Leave the current game.
class GuessmeLeaveGame extends GuessmeEvent {
  const GuessmeLeaveGame();
}

// ==================== INTERNAL EVENTS ====================

class _GuessmeSessionUpdated extends GuessmeEvent {
  final GuessmeSession? session;

  const _GuessmeSessionUpdated(this.session);

  @override
  List<Object?> get props => [session];
}

class _GuessmeMessagesUpdated extends GuessmeEvent {
  final List<GuessmeMessage> messages;

  const _GuessmeMessagesUpdated(this.messages);

  @override
  List<Object?> get props => [messages];
}

class _GuessmeStatsUpdated extends GuessmeEvent {
  final GuessmeStats stats;

  const _GuessmeStatsUpdated(this.stats);

  @override
  List<Object?> get props => [stats];
}

class _GuessmeSessionExpired extends GuessmeEvent {
  const _GuessmeSessionExpired();
}

/// Mark user as actively searching for a GuessMe match.
class GuessmeMarkSearching extends GuessmeEvent {
  final String userId;

  const GuessmeMarkSearching(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Clear user's searching status.
class GuessmeClearSearching extends GuessmeEvent {
  final String userId;

  const GuessmeClearSearching(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Ensure the BLoC is subscribed to the specified session.
/// Used when game page opens to guarantee messages are streaming.
class GuessmeEnsureSessionSubscription extends GuessmeEvent {
  final String sessionId;

  const GuessmeEnsureSessionSubscription(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}
