import 'package:equatable/equatable.dart';

/// Type of group message content.
enum GroupMessageType {
  /// Text message.
  text,

  /// Image message.
  image,

  /// System message (e.g., "X joined the group").
  system,
}

/// Entity representing a message in a location group chat.
class GroupMessage extends Equatable {
  /// Unique message ID.
  final String id;

  /// Group ID this message belongs to.
  final String groupId;

  /// User ID who sent the message.
  final String senderId;

  /// Sender's display name at time of sending.
  final String? senderName;

  /// Sender's photo URL at time of sending.
  final String? senderPhotoUrl;

  /// Message text content.
  final String text;

  /// Type of message.
  final GroupMessageType type;

  /// URL to media file (for image messages).
  final String? mediaUrl;

  /// When the message was sent.
  final DateTime sentAt;

  /// Whether this message has been deleted (soft delete).
  final bool isDeleted;

  /// Local-only: optimistic ID for pending messages.
  final String? localId;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.senderName,
    this.senderPhotoUrl,
    required this.text,
    this.type = GroupMessageType.text,
    this.mediaUrl,
    required this.sentAt,
    this.isDeleted = false,
    this.localId,
  });

  /// Whether this message is from the given user.
  bool isFromUser(String userId) => senderId == userId;

  /// Whether this is a system-generated message.
  bool get isSystemMessage => type == GroupMessageType.system;

  /// Whether this message has media attached.
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  GroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? senderName,
    String? senderPhotoUrl,
    String? text,
    GroupMessageType? type,
    String? mediaUrl,
    DateTime? sentAt,
    bool? isDeleted,
    String? localId,
  }) {
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      sentAt: sentAt ?? this.sentAt,
      isDeleted: isDeleted ?? this.isDeleted,
      localId: localId ?? this.localId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        senderId,
        senderName,
        senderPhotoUrl,
        text,
        type,
        mediaUrl,
        sentAt,
        isDeleted,
        localId,
      ];
}
