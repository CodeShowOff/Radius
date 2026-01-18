import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/guess_me_stats.dart';

/// Firestore model for GuessMe stats.
class GuessmeStatsModel extends GuessmeStats {
  const GuessmeStatsModel({
    super.gamesPlayed,
    super.correctGuesses,
    super.timesGuessed,
    super.currentStreak,
    super.bestStreak,
    super.lastPlayed,
  });

  factory GuessmeStatsModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return const GuessmeStatsModel();

    return GuessmeStatsModel(
      gamesPlayed: data['gamesPlayed'] as int? ?? 0,
      correctGuesses: data['correctGuesses'] as int? ?? 0,
      timesGuessed: data['timesGuessed'] as int? ?? 0,
      currentStreak: data['currentStreak'] as int? ?? 0,
      bestStreak: data['bestStreak'] as int? ?? 0,
      lastPlayed: data['lastPlayed'] != null
          ? (data['lastPlayed'] as Timestamp).toDate()
          : null,
    );
  }

  factory GuessmeStatsModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const GuessmeStatsModel();

    return GuessmeStatsModel(
      gamesPlayed: data['gamesPlayed'] as int? ?? 0,
      correctGuesses: data['correctGuesses'] as int? ?? 0,
      timesGuessed: data['timesGuessed'] as int? ?? 0,
      currentStreak: data['currentStreak'] as int? ?? 0,
      bestStreak: data['bestStreak'] as int? ?? 0,
      lastPlayed: data['lastPlayed'] != null
          ? (data['lastPlayed'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'gamesPlayed': gamesPlayed,
      'correctGuesses': correctGuesses,
      'timesGuessed': timesGuessed,
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'lastPlayed': lastPlayed != null ? Timestamp.fromDate(lastPlayed!) : null,
    };
  }

  GuessmeStats toEntity() {
    return GuessmeStats(
      gamesPlayed: gamesPlayed,
      correctGuesses: correctGuesses,
      timesGuessed: timesGuessed,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      lastPlayed: lastPlayed,
    );
  }
}
