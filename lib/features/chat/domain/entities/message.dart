import 'package:equatable/equatable.dart';

/// Status of a message in the chat.
enum MessageStatus {
  /// Message is being sent.
  sending,

  /// Message was sent to server.
  sent,

  /// Message was delivered to recipient's device.
  delivered,

  /// Message was read by recipient.
  read,

  /// Message failed to send.
  failed,
}

/// Entity representing a chat message.
class Message extends Equatable {
  /// Unique message ID.
  final String id;

  /// Conversation/chat ID this message belongs to.
  final String conversationId;

  /// User ID who sent the message.
  final String senderId;

  /// Message text content.
  final String text;

  /// When the message was sent.
  final DateTime sentAt;

  /// When the message was delivered (null if not yet delivered).
  final DateTime? deliveredAt;

  /// When the message was read (null if not yet read).
  final DateTime? readAt;

  /// Current status of the message.
  final MessageStatus status;

  /// Whether this message has been deleted (soft delete).
  final bool isDeleted;

  /// Local-only: optimistic ID for pending messages.
  final String? localId;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.status = MessageStatus.sent,
    this.isDeleted = false,
    this.localId,
  });

  /// Whether this message was sent by the given user.
  bool isSentBy(String userId) => senderId == userId;

  /// Whether this message has been read.
  bool get isRead => readAt != null || status == MessageStatus.read;

  /// Whether this message has been delivered.
  bool get isDelivered =>
      deliveredAt != null ||
      status == MessageStatus.delivered ||
      status == MessageStatus.read;

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? text,
    DateTime? sentAt,
    Object? deliveredAt = _sentinel,
    Object? readAt = _sentinel,
    MessageStatus? status,
    bool? isDeleted,
    Object? localId = _sentinel,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt == _sentinel
          ? this.deliveredAt
          : deliveredAt as DateTime?,
      readAt: readAt == _sentinel ? this.readAt : readAt as DateTime?,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      localId: localId == _sentinel ? this.localId : localId as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        conversationId,
        senderId,
        text,
        sentAt,
        deliveredAt,
        readAt,
        status,
        isDeleted,
        localId,
      ];
}
