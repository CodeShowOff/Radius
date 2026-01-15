import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/message.dart';

/// Firestore model for Message entity.
/// 
/// Firestore Schema:
/// ```
/// conversations/{conversationId}/messages/{messageId}
///   - senderId: string
///   - text: string
///   - sentAt: timestamp
///   - deliveredAt: timestamp?
///   - readAt: timestamp?
///   - status: string ('sending', 'sent', 'delivered', 'read', 'failed')
///   - isDeleted: boolean
/// ```
class MessageModel extends Message {
  const MessageModel({
    required super.id,
    required super.conversationId,
    required super.senderId,
    required super.text,
    required super.sentAt,
    super.deliveredAt,
    super.readAt,
    super.status,
    super.isDeleted,
    super.localId,
  });

  /// Creates model from Firestore document.
  factory MessageModel.fromFirestore(
    DocumentSnapshot doc,
    String conversationId,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    return MessageModel(
      id: doc.id,
      conversationId: conversationId,
      senderId: data['senderId'] as String,
      text: data['text'] as String,
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      deliveredAt: data['deliveredAt'] != null
          ? (data['deliveredAt'] as Timestamp).toDate()
          : null,
      readAt: data['readAt'] != null
          ? (data['readAt'] as Timestamp).toDate()
          : null,
      status: _parseStatus(data['status'] as String? ?? 'sent'),
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  /// Creates model from Message entity.
  factory MessageModel.fromEntity(Message message) {
    return MessageModel(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      text: message.text,
      sentAt: message.sentAt,
      deliveredAt: message.deliveredAt,
      readAt: message.readAt,
      status: message.status,
      isDeleted: message.isDeleted,
      localId: message.localId,
    );
  }

  /// Creates an optimistic message (for immediate UI update).
  factory MessageModel.optimistic({
    required String localId,
    required String conversationId,
    required String senderId,
    required String text,
  }) {
    return MessageModel(
      id: localId, // Temporary ID
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      sentAt: DateTime.now(),
      status: MessageStatus.sending,
      localId: localId,
    );
  }

  /// Converts to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
      'deliveredAt': deliveredAt != null
          ? Timestamp.fromDate(deliveredAt!)
          : null,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'status': status.name,
      'isDeleted': isDeleted,
    };
  }

  /// Converts to Message entity.
  Message toEntity() {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      sentAt: sentAt,
      deliveredAt: deliveredAt,
      readAt: readAt,
      status: status,
      isDeleted: isDeleted,
      localId: localId,
    );
  }

  static MessageStatus _parseStatus(String status) {
    return MessageStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => MessageStatus.sent,
    );
  }
}
