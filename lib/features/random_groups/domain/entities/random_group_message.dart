import 'package:equatable/equatable.dart';

/// Type of message in a random group chat.
enum RandomGroupMessageType {
  /// Regular text message
  text,

  /// System message (join/leave notifications, etc.)
  system,
}

/// Entity representing a message in a random group chat.
class RandomGroupMessage extends Equatable {
  /// Unique message ID
  final String id;

  /// Group ID this message belongs to
  final String groupId;

  /// Sender's user ID (null for system messages)
  final String? senderId;

  /// Sender's username (null for system messages)
  final String? senderUsername;

  /// Sender's display name (null for system messages)
  final String? senderName;

  /// Sender's photo URL (null for system messages)
  final String? senderPhotoUrl;

  /// Message text content
  final String text;

  /// Message type
  final RandomGroupMessageType type;

  /// When the message was sent
  final DateTime sentAt;

  const RandomGroupMessage({
    required this.id,
    required this.groupId,
    this.senderId,
    this.senderUsername,
    this.senderName,
    this.senderPhotoUrl,
    required this.text,
    required this.type,
    required this.sentAt,
  });

  /// Check if this is a system message
  bool get isSystemMessage => type == RandomGroupMessageType.system;

  /// Check if this message was sent by a specific user
  bool isSentBy(String userId) => senderId == userId;

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
      ];
}
