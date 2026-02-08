import 'package:equatable/equatable.dart';

/// An active random chat connection between two users for the current day.
class RandomChatConnection extends Equatable {
  final String id;
  final String user1Id;
  final String user2Id;
  final String user1DisplayName;
  final String? user1PhotoUrl;
  final String user2DisplayName;
  final String? user2PhotoUrl;
  final String dateKey; // e.g. '2026-02-09'
  final DateTime createdAt;

  const RandomChatConnection({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    required this.user1DisplayName,
    this.user1PhotoUrl,
    required this.user2DisplayName,
    this.user2PhotoUrl,
    required this.dateKey,
    required this.createdAt,
  });

  /// Get the other user's ID.
  String getOtherUserId(String currentUserId) {
    return currentUserId == user1Id ? user2Id : user1Id;
  }

  /// Get the other user's display name.
  String getOtherUserName(String currentUserId) {
    return currentUserId == user1Id ? user2DisplayName : user1DisplayName;
  }

  /// Get the other user's photo URL.
  String? getOtherUserPhotoUrl(String currentUserId) {
    return currentUserId == user1Id ? user2PhotoUrl : user1PhotoUrl;
  }

  @override
  List<Object?> get props => [
        id,
        user1Id,
        user2Id,
        user1DisplayName,
        user1PhotoUrl,
        user2DisplayName,
        user2PhotoUrl,
        dateKey,
        createdAt,
      ];
}
