import 'package:equatable/equatable.dart';

/// User's GuessMe game statistics and badges.
class GuessmeStats extends Equatable {
  /// Total number of games played.
  final int gamesPlayed;

  /// Number of correct guesses made by this user.
  final int correctGuesses;

  /// Number of times this user was correctly guessed.
  final int timesGuessed;

  /// Current winning streak.
  final int currentStreak;

  /// Best winning streak ever.
  final int bestStreak;

  /// Last game played timestamp.
  final DateTime? lastPlayed;

  const GuessmeStats({
    this.gamesPlayed = 0,
    this.correctGuesses = 0,
    this.timesGuessed = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastPlayed,
  });

  /// Returns the badge tier based on correct guesses.
  GuessmeBadgeTier get badgeTier {
    if (correctGuesses >= 100) return GuessmeBadgeTier.master;
    if (correctGuesses >= 50) return GuessmeBadgeTier.expert;
    if (correctGuesses >= 25) return GuessmeBadgeTier.skilled;
    if (correctGuesses >= 10) return GuessmeBadgeTier.intermediate;
    if (correctGuesses >= 5) return GuessmeBadgeTier.beginner;
    return GuessmeBadgeTier.none;
  }

  /// Alias for badgeTier for convenience.
  GuessmeBadgeTier get badge => badgeTier;

  /// Returns the next badge tier to achieve.
  GuessmeBadgeTier? get nextBadge {
    switch (badgeTier) {
      case GuessmeBadgeTier.none:
        return GuessmeBadgeTier.beginner;
      case GuessmeBadgeTier.beginner:
        return GuessmeBadgeTier.intermediate;
      case GuessmeBadgeTier.intermediate:
        return GuessmeBadgeTier.skilled;
      case GuessmeBadgeTier.skilled:
        return GuessmeBadgeTier.expert;
      case GuessmeBadgeTier.expert:
        return GuessmeBadgeTier.master;
      case GuessmeBadgeTier.master:
        return null; // Already at max
    }
  }

  /// Progress percentage to next badge (0.0 to 1.0).
  double get progressToNextBadge {
    final next = nextBadge;
    if (next == null) return 1.0;
    final currentThreshold = badgeTier.requiredGuesses;
    final nextThreshold = next.requiredGuesses;
    final progress = (correctGuesses - currentThreshold) /
        (nextThreshold - currentThreshold);
    return progress.clamp(0.0, 1.0);
  }

  /// Returns true if user has any badge.
  bool get hasBadge => badgeTier != GuessmeBadgeTier.none;

  /// Success rate percentage.
  double get successRate {
    if (gamesPlayed == 0) return 0;
    return (correctGuesses / gamesPlayed) * 100;
  }

  GuessmeStats copyWith({
    int? gamesPlayed,
    int? correctGuesses,
    int? timesGuessed,
    int? currentStreak,
    int? bestStreak,
    DateTime? lastPlayed,
  }) {
    return GuessmeStats(
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      correctGuesses: correctGuesses ?? this.correctGuesses,
      timesGuessed: timesGuessed ?? this.timesGuessed,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }

  @override
  List<Object?> get props => [
        gamesPlayed,
        correctGuesses,
        timesGuessed,
        currentStreak,
        bestStreak,
        lastPlayed,
      ];
}

/// Badge tiers for GuessMe achievements.
enum GuessmeBadgeTier {
  none,
  beginner, // 5 correct guesses
  intermediate, // 10 correct guesses
  skilled, // 25 correct guesses
  expert, // 50 correct guesses
  master, // 100 correct guesses
}

extension GuessmeBadgeTierX on GuessmeBadgeTier {
  String get displayName {
    switch (this) {
      case GuessmeBadgeTier.none:
        return 'No Badge';
      case GuessmeBadgeTier.beginner:
        return 'Beginner Guesser';
      case GuessmeBadgeTier.intermediate:
        return 'Rising Guesser';
      case GuessmeBadgeTier.skilled:
        return 'Skilled Guesser';
      case GuessmeBadgeTier.expert:
        return 'Expert Guesser';
      case GuessmeBadgeTier.master:
        return 'Master Guesser';
    }
  }

  String get emoji {
    switch (this) {
      case GuessmeBadgeTier.none:
        return '';
      case GuessmeBadgeTier.beginner:
        return '🔮';
      case GuessmeBadgeTier.intermediate:
        return '🎯';
      case GuessmeBadgeTier.skilled:
        return '⭐';
      case GuessmeBadgeTier.expert:
        return '🏆';
      case GuessmeBadgeTier.master:
        return '👑';
    }
  }

  /// Icon for the badge tier.
  int get iconCodePoint {
    switch (this) {
      case GuessmeBadgeTier.none:
        return 0xe8f4; // Icons.help_outline
      case GuessmeBadgeTier.beginner:
        return 0xea64; // Icons.psychology
      case GuessmeBadgeTier.intermediate:
        return 0xe838; // Icons.trending_up
      case GuessmeBadgeTier.skilled:
        return 0xe838; // Icons.star
      case GuessmeBadgeTier.expert:
        return 0xe8f6; // Icons.emoji_events
      case GuessmeBadgeTier.master:
        return 0xea23; // Icons.military_tech
    }
  }

  /// Color for the badge tier (as int for cross-platform).
  int get colorValue {
    switch (this) {
      case GuessmeBadgeTier.none:
        return 0xFF9E9E9E; // Grey
      case GuessmeBadgeTier.beginner:
        return 0xFF8BC34A; // Light green
      case GuessmeBadgeTier.intermediate:
        return 0xFF2196F3; // Blue
      case GuessmeBadgeTier.skilled:
        return 0xFF9C27B0; // Purple
      case GuessmeBadgeTier.expert:
        return 0xFFFF9800; // Orange
      case GuessmeBadgeTier.master:
        return 0xFFFFD700; // Gold
    }
  }

  int get requiredGuesses {
    switch (this) {
      case GuessmeBadgeTier.none:
        return 0;
      case GuessmeBadgeTier.beginner:
        return 5;
      case GuessmeBadgeTier.intermediate:
        return 10;
      case GuessmeBadgeTier.skilled:
        return 25;
      case GuessmeBadgeTier.expert:
        return 50;
      case GuessmeBadgeTier.master:
        return 100;
    }
  }
}
