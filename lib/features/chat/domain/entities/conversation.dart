import 'package:equatable/equatable.dart';

/// Entity representing a conversation between two users.
class Conversation extends Equatable {
  /// Unique conversation ID (canonical format: smaller_larger user IDs).
  final String id;

  /// List of participant user IDs (always 2 for 1-to-1).
  final List<String> participantIds;

  /// When the conversation was created.
  final DateTime createdAt;

  /// When the last message was sent.
  final DateTime? lastMessageAt;

  /// Preview of the last message.
  final String? lastMessageText;

  /// Sender ID of the last message.
  final String? lastMessageSenderId;

  /// Whether the conversation is muted for each participant.
  /// Map\<userId, isMuted\>
  final Map<String, bool> mutedBy;

  /// Participant info (denormalized for fast UI).
  /// Map\<userId, {displayName, photoUrl}\>
  final Map<String, ParticipantInfo> participantInfo;

  /// Whether either user has archived this conversation.
  final Map<String, bool> archivedBy;

  /// Unread message counts per user (userId -> count).
  final Map<String, int> unreadCounts;

  /// Last read timestamps per user (userId -> timestamp).
  final Map<String, DateTime> lastReadAt;

  const Conversation({
    required this.id,
    required this.participantIds,
    required this.createdAt,
    this.lastMessageAt,
    this.lastMessageText,
    this.lastMessageSenderId,
    this.mutedBy = const {},
    this.participantInfo = const {},
    this.archivedBy = const {},
    this.unreadCounts = const {},
    this.lastReadAt = const {},
  });

  /// Creates a canonical conversation ID from two user IDs.
  static String createConversationId(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  /// Gets the other participant's ID.
  String getOtherParticipantId(String currentUserId) {
    return participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => participantIds.first,
    );
  }

  /// Checks if muted by a user.
  bool isMutedBy(String userId) => mutedBy[userId] ?? false;

  /// Checks if archived by a user.
  bool isArchivedBy(String userId) => archivedBy[userId] ?? false;

  /// Gets unread count for a specific user.
  int getUnreadCount(String userId) => unreadCounts[userId] ?? 0;

  /// Gets last read timestamp for a specific user.
  DateTime? getLastReadAt(String userId) => lastReadAt[userId];

  /// Gets participant info for the other user.
  ParticipantInfo? getOtherParticipantInfo(String currentUserId) {
    final otherId = getOtherParticipantId(currentUserId);
    return participantInfo[otherId];
  }

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  Conversation copyWith({
    String? id,
    List<String>? participantIds,
    DateTime? createdAt,
    Object? lastMessageAt = _sentinel,
    Object? lastMessageText = _sentinel,
    Object? lastMessageSenderId = _sentinel,
    Map<String, bool>? mutedBy,
    Map<String, ParticipantInfo>? participantInfo,
    Map<String, bool>? archivedBy,
    Map<String, int>? unreadCounts,
    Map<String, DateTime>? lastReadAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      participantIds: participantIds ?? this.participantIds,
      createdAt: createdAt ?? this.createdAt,
      lastMessageAt: lastMessageAt == _sentinel
          ? this.lastMessageAt
          : lastMessageAt as DateTime?,
      lastMessageText: lastMessageText == _sentinel
          ? this.lastMessageText
          : lastMessageText as String?,
      lastMessageSenderId: lastMessageSenderId == _sentinel
          ? this.lastMessageSenderId
          : lastMessageSenderId as String?,
      mutedBy: mutedBy ?? this.mutedBy,
      participantInfo: participantInfo ?? this.participantInfo,
      archivedBy: archivedBy ?? this.archivedBy,
      unreadCounts: unreadCounts ?? this.unreadCounts,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        participantIds,
        createdAt,
        lastMessageAt,
        lastMessageText,
        lastMessageSenderId,
        mutedBy,
        participantInfo,
        archivedBy,
        unreadCounts,
        lastReadAt,
      ];
}

/// Denormalized participant info for fast UI rendering.
class ParticipantInfo extends Equatable {
  final String displayName;
  final String? photoUrl;
  final bool isOnline;
  final DateTime? lastSeen;

  const ParticipantInfo({
    required this.displayName,
    this.photoUrl,
    this.isOnline = false,
    this.lastSeen,
  });

  @override
  List<Object?> get props => [displayName, photoUrl, isOnline, lastSeen];
}
