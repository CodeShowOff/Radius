import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/message.dart';

/// Firestore model for Message entity.
///
/// Firestore Schema:
/// ```
/// conversations/{conversationId}/messages/{messageId}
///   - senderId: string
///   - text: string
///   - type: string ('text', 'image', 'audio', 'document', 'sticker', 'video')
///   - mediaUrl: string?
///   - mediaFileName: string?
///   - mediaFileSize: number?
///   - duration: number? (seconds)
///   - thumbnailUrl: string?
///   - sentAt: timestamp
///   - isDeleted: boolean
///   - localId: string? (client-side optimistic ID for deduplication)
/// ```
class MessageModel extends Message {
  const MessageModel({
    required super.id,
    required super.conversationId,
    required super.senderId,
    required super.text,
    super.type,
    super.mediaUrl,
    super.mediaFileName,
    super.mediaFileSize,
    super.duration,
    super.thumbnailUrl,
    required super.sentAt,
    super.isDeleted,
    super.localId,
    super.uploadProgress,
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
      text: data['text'] as String? ?? '',
      type: _parseType(data['type'] as String? ?? 'text'),
      mediaUrl: data['mediaUrl'] as String?,
      mediaFileName: data['mediaFileName'] as String?,
      mediaFileSize: data['mediaFileSize'] as int?,
      duration: data['duration'] as int?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      sentAt: data['sentAt'] != null
          ? (data['sentAt'] as Timestamp).toDate()
          : DateTime.now(), // Handle null during optimistic send
      isDeleted: data['isDeleted'] as bool? ?? false,
      localId: data['localId'] as String?, // Read localId for matching
    );
  }

  /// Creates model from Message entity.
  factory MessageModel.fromEntity(Message message) {
    return MessageModel(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      text: message.text,
      type: message.type,
      mediaUrl: message.mediaUrl,
      mediaFileName: message.mediaFileName,
      mediaFileSize: message.mediaFileSize,
      duration: message.duration,
      thumbnailUrl: message.thumbnailUrl,
      sentAt: message.sentAt,
      isDeleted: message.isDeleted,
      localId: message.localId,
      uploadProgress: message.uploadProgress,
    );
  }

  /// Creates an optimistic message (for immediate UI update).
  factory MessageModel.optimistic({
    required String localId,
    required String conversationId,
    required String senderId,
    required String text,
    MessageType type = MessageType.text,
    String? mediaUrl,
    String? mediaFileName,
    int? mediaFileSize,
    int? duration,
    String? thumbnailUrl,
    double? uploadProgress,
  }) {
    return MessageModel(
      id: localId, // Temporary ID
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      type: type,
      mediaUrl: mediaUrl,
      mediaFileName: mediaFileName,
      mediaFileSize: mediaFileSize,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      sentAt: DateTime.now(),
      localId: localId,
      uploadProgress: uploadProgress,
    );
  }

  /// Converts to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'type': type.name,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaFileName != null) 'mediaFileName': mediaFileName,
      if (mediaFileSize != null) 'mediaFileSize': mediaFileSize,
      if (duration != null) 'duration': duration,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': isDeleted,
      if (localId != null) 'localId': localId, // Store for optimistic matching
    };
  }

  /// Converts to Message entity.
  Message toEntity() {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      type: type,
      mediaUrl: mediaUrl,
      mediaFileName: mediaFileName,
      mediaFileSize: mediaFileSize,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      sentAt: sentAt,
      isDeleted: isDeleted,
      localId: localId,
      uploadProgress: uploadProgress,
    );
  }

  static MessageType _parseType(String value) {
    switch (value) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'audio':
        return MessageType.audio;
      case 'document':
        return MessageType.document;
      case 'sticker':
        return MessageType.sticker;
      case 'video':
        return MessageType.video;
      default:
        return MessageType.text;
    }
  }
}
