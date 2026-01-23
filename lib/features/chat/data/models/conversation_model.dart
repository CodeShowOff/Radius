import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// Firestore model for Conversation entity.
///
/// Firestore Schema:
/// ```
/// conversations/{conversationId}
///   - participantIds: [string, string]
///   - createdAt: timestamp
///   - lastMessageAt: timestamp?
///   - lastMessageText: string?
///   - lastMessageSenderId: string?
///   - lastMessageStatus: string?
///   - unreadCounts: { [userId]: number }
///   - lastReadAt: { [userId]: timestamp }  // When user last read messages
///   - mutedBy: { [userId]: boolean }
///   - archivedBy: { [userId]: boolean }
///   - participantInfo: {
///       [userId]: { displayName: string, photoUrl: string? }
///     }
/// ```
class ConversationModel extends Conversation {
  const ConversationModel({
    required super.id,
    required super.participantIds,
    required super.createdAt,
    super.lastMessageAt,
    super.lastMessageText,
    super.lastMessageSenderId,
    super.lastMessageStatus,
    super.unreadCounts,
    super.mutedBy,
    super.participantInfo,
    super.archivedBy,
    super.lastReadAt,
  });

  /// Creates model from Firestore document.
  factory ConversationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse participant info
    final participantInfoData =
        data['participantInfo'] as Map<String, dynamic>? ?? {};
    final participantInfo = participantInfoData.map(
      (key, value) => MapEntry(
        key,
        ParticipantInfo(
          displayName:
              (value as Map<String, dynamic>)['displayName'] as String? ??
                  'Unknown',
          photoUrl: value['photoUrl'] as String?,
          isOnline: value['isOnline'] as bool? ?? false,
          lastSeen: value['lastSeen'] != null
              ? (value['lastSeen'] as Timestamp).toDate()
              : null,
        ),
      ),
    );

    // Parse unread counts
    final unreadCountsData =
        data['unreadCounts'] as Map<String, dynamic>? ?? {};
    final unreadCounts = unreadCountsData.map(
      (key, value) => MapEntry(key, (value as num).toInt()),
    );

    // Parse muted/archived
    final mutedByData = data['mutedBy'] as Map<String, dynamic>? ?? {};
    final mutedBy = mutedByData.map(
      (key, value) => MapEntry(key, value as bool),
    );

    final archivedByData = data['archivedBy'] as Map<String, dynamic>? ?? {};
    final archivedBy = archivedByData.map(
      (key, value) => MapEntry(key, value as bool),
    );

    // Parse lastReadAt timestamps
    final lastReadAtData = data['lastReadAt'] as Map<String, dynamic>? ?? {};
    final lastReadAt = lastReadAtData.map(
      (key, value) => MapEntry(key, (value as Timestamp).toDate()),
    );

    return ConversationModel(
      id: doc.id,
      participantIds: List<String>.from(data['participantIds'] as List),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastMessageAt: data['lastMessageAt'] != null
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : null,
      lastMessageText: data['lastMessageText'] as String?,
      lastMessageSenderId: data['lastMessageSenderId'] as String?,
      lastMessageStatus: data['lastMessageStatus'] != null
          ? _parseStatus(data['lastMessageStatus'] as String)
          : null,
      unreadCounts: unreadCounts,
      mutedBy: mutedBy,
      participantInfo: participantInfo,
      archivedBy: archivedBy,
      lastReadAt: lastReadAt,
    );
  }

  /// Creates model from Conversation entity.
  factory ConversationModel.fromEntity(Conversation conversation) {
    return ConversationModel(
      id: conversation.id,
      participantIds: conversation.participantIds,
      createdAt: conversation.createdAt,
      lastMessageAt: conversation.lastMessageAt,
      lastMessageText: conversation.lastMessageText,
      lastMessageSenderId: conversation.lastMessageSenderId,
      lastMessageStatus: conversation.lastMessageStatus,
      unreadCounts: conversation.unreadCounts,
      mutedBy: conversation.mutedBy,
      participantInfo: conversation.participantInfo,
      archivedBy: conversation.archivedBy,
      lastReadAt: conversation.lastReadAt,
    );
  }

  /// Creates a new conversation between two users.
  factory ConversationModel.create({
    required String currentUserId,
    required String otherUserId,
    required String currentUserName,
    required String otherUserName,
    String? currentUserPhotoUrl,
    String? otherUserPhotoUrl,
  }) {
    final conversationId =
        Conversation.createConversationId(currentUserId, otherUserId);
    final participants = [currentUserId, otherUserId]..sort();
    final now = DateTime.now();

    return ConversationModel(
      id: conversationId,
      participantIds: participants,
      createdAt: now,
      lastMessageAt: now, // Required by Firestore security rules
      unreadCounts: {currentUserId: 0, otherUserId: 0},
      mutedBy: const {},
      participantInfo: {
        currentUserId: ParticipantInfo(
          displayName: currentUserName,
          photoUrl: currentUserPhotoUrl,
        ),
        otherUserId: ParticipantInfo(
          displayName: otherUserName,
          photoUrl: otherUserPhotoUrl,
        ),
      },
      archivedBy: const {},
      lastReadAt: {currentUserId: now, otherUserId: now}, // Initialize lastReadAt
    );
  }

  /// Converts to Firestore document data.
  /// When [useServerTimestamp] is true, createdAt will use FieldValue.serverTimestamp()
  /// which is required by Firestore security rules for document creation.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    // Extract participant names from participantInfo for security rules
    final participantNames = participantInfo.map(
      (key, value) => MapEntry(key, value.displayName),
    );

    return {
      'id': id, // Required by Firestore security rules
      'participantIds': participantIds,
      'participantNames': participantNames, // Required by Firestore security rules
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt),
      // Defensive: lastMessageAt must NEVER be null to satisfy Firestore rules
      // If lastMessageAt is somehow null, fall back to createdAt
      'lastMessageAt': lastMessageAt != null 
          ? Timestamp.fromDate(lastMessageAt!)
          : Timestamp.fromDate(createdAt),
      'lastMessageText': lastMessageText,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageStatus': lastMessageStatus?.name,
      'unreadCounts': unreadCounts,
      'lastReadAt': lastReadAt.map(
        (key, value) => MapEntry(key, Timestamp.fromDate(value)),
      ),
      'mutedBy': mutedBy,
      'archivedBy': archivedBy,
      'participantInfo': participantInfo.map(
        (key, value) => MapEntry(key, {
          'displayName': value.displayName,
          'photoUrl': value.photoUrl,
          'isOnline': value.isOnline,
          'lastSeen': value.lastSeen != null
              ? Timestamp.fromDate(value.lastSeen!)
              : null,
        }),
      ),
    };
  }

  /// Converts to Conversation entity.
  Conversation toEntity() {
    return Conversation(
      id: id,
      participantIds: participantIds,
      createdAt: createdAt,
      lastMessageAt: lastMessageAt,
      lastMessageText: lastMessageText,
      lastMessageSenderId: lastMessageSenderId,
      lastMessageStatus: lastMessageStatus,
      unreadCounts: unreadCounts,
      mutedBy: mutedBy,
      participantInfo: participantInfo,
      archivedBy: archivedBy,
      lastReadAt: lastReadAt,
    );
  }

  static MessageStatus _parseStatus(String status) {
    return MessageStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => MessageStatus.sent,
    );
  }
}
