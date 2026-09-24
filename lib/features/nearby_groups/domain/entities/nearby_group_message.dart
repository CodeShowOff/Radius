import 'package:equatable/equatable.dart';

import '../../../../core/enums/group_message_status.dart';

/// Type of message in nearby group chat.
enum NearbyGroupMessageType {
  /// Regular text message from a user
  text,

  /// System message (user joined, left, etc.)
  system,
}

/// Entity representing a message in a nearby group chat.
class NearbyGroupMessage extends Equatable {
  /// Unique identifier for the message
  final String id;

  /// ID of the group this message belongs to
  final String groupId;

  /// User ID of the sender (null for system messages)
  final String? senderId;

  /// Sender's username
  final String? senderUsername;

  /// Sender's display name
  final String? senderName;

  /// Sender's photo URL
  final String? senderPhotoUrl;

  /// Message text content
  final String text;

  /// Message type
  final NearbyGroupMessageType type;

  /// When the message was sent
  final DateTime sentAt;

  /// Whether this message has been deleted (soft delete).
  final bool isDeleted;

  /// Client-side optimistic ID for deduplication.
  final String? localId;

  /// Message send status (pending, sent, error).
  final GroupMessageStatus status;

  const NearbyGroupMessage({
    required this.id,
    required this.groupId,
    this.senderId,
    this.senderUsername,
    this.senderName,
    this.senderPhotoUrl,
    required this.text,
    required this.type,
    required this.sentAt,
    this.isDeleted = false,
    this.localId,
    this.status = GroupMessageStatus.sent,
  });

  /// Whether this is a system message
  bool get isSystemMessage => type == NearbyGroupMessageType.system;

  /// Whether this message was sent by the given user
  bool isSentBy(String userId) => senderId == userId;

  /// Whether this message can be retried (failed to send).
  bool get canRetry => status == GroupMessageStatus.error;

  /// Whether this message is still pending confirmation.
  bool get isPending => status == GroupMessageStatus.pending;

  /// Creates a copy with updated fields
  NearbyGroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? senderUsername,
    String? senderName,
    String? senderPhotoUrl,
    String? text,
    NearbyGroupMessageType? type,
    DateTime? sentAt,
    bool? isDeleted,
    String? localId,
    GroupMessageStatus? status,
  }) {
    return NearbyGroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
      text: text ?? this.text,
      type: type ?? this.type,
      sentAt: sentAt ?? this.sentAt,
      isDeleted: isDeleted ?? this.isDeleted,
      localId: localId ?? this.localId,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        senderId,
        senderUsername,
        senderName,
        senderPhotoUrl,
        text,
        type,
        sentAt,
        isDeleted,
        localId,
        status,
      ];

  @override
  String toString() {
    return 'NearbyGroupMessage(id: $id, senderId: $senderId, text: ${text.length > 50 ? '${text.substring(0, 50)}...' : text})';
  }
}
