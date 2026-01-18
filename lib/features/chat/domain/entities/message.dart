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

/// Type of message content.
enum MessageType {
  /// Text message.
  text,

  /// Image message.
  image,

  /// Audio/voice message.
  audio,

  /// Document file.
  document,

  /// Sticker.
  sticker,

  /// Video message.
  video,
}

/// Entity representing a chat message.
class Message extends Equatable {
  /// Unique message ID.
  final String id;

  /// Conversation/chat ID this message belongs to.
  final String conversationId;

  /// User ID who sent the message.
  final String senderId;

  /// Message text content (empty for media-only messages).
  final String text;

  /// Type of message (text, image, audio, etc.).
  final MessageType type;

  /// URL to media file in Firebase Storage (for non-text messages).
  final String? mediaUrl;

  /// Original filename of uploaded media.
  final String? mediaFileName;

  /// Size of media file in bytes.
  final int? mediaFileSize;

  /// Duration in seconds (for audio/video messages).
  final int? duration;

  /// Thumbnail URL for videos/documents.
  final String? thumbnailUrl;

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

  /// Upload progress (0.0 to 1.0) for media uploads.
  final double? uploadProgress;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    this.type = MessageType.text,
    this.mediaUrl,
    this.mediaFileName,
    this.mediaFileSize,
    this.duration,
    this.thumbnailUrl,
    required this.sentAt,
    this.deliveredAt,
    this.readAt,
    this.status = MessageStatus.sent,
    this.isDeleted = false,
    this.localId,
    this.uploadProgress,
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

  /// Whether this is a media message.
  bool get isMediaMessage => type != MessageType.text;

  /// Whether media is still uploading.
  bool get isUploading =>
      isMediaMessage && uploadProgress != null && uploadProgress! < 1.0;

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? text,
    MessageType? type,
    Object? mediaUrl = _sentinel,
    Object? mediaFileName = _sentinel,
    Object? mediaFileSize = _sentinel,
    Object? duration = _sentinel,
    Object? thumbnailUrl = _sentinel,
    DateTime? sentAt,
    Object? deliveredAt = _sentinel,
    Object? readAt = _sentinel,
    MessageStatus? status,
    bool? isDeleted,
    Object? localId = _sentinel,
    Object? uploadProgress = _sentinel,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaUrl: mediaUrl == _sentinel ? this.mediaUrl : mediaUrl as String?,
      mediaFileName: mediaFileName == _sentinel
          ? this.mediaFileName
          : mediaFileName as String?,
      mediaFileSize: mediaFileSize == _sentinel
          ? this.mediaFileSize
          : mediaFileSize as int?,
      duration: duration == _sentinel ? this.duration : duration as int?,
      thumbnailUrl: thumbnailUrl == _sentinel
          ? this.thumbnailUrl
          : thumbnailUrl as String?,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: deliveredAt == _sentinel
          ? this.deliveredAt
          : deliveredAt as DateTime?,
      readAt: readAt == _sentinel ? this.readAt : readAt as DateTime?,
      status: status ?? this.status,
      isDeleted: isDeleted ?? this.isDeleted,
      localId: localId == _sentinel ? this.localId : localId as String?,
      uploadProgress: uploadProgress == _sentinel
          ? this.uploadProgress
          : uploadProgress as double?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        conversationId,
        senderId,
        text,
        type,
        mediaUrl,
        mediaFileName,
        mediaFileSize,
        duration,
        thumbnailUrl,
        sentAt,
        deliveredAt,
        readAt,
        status,
        isDeleted,
        localId,
        uploadProgress,
      ];
}
