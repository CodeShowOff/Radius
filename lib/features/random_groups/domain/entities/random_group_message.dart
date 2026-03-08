import 'package:equatable/equatable.dart';

import '../../../../core/widgets/group_message_bubble.dart';

/// Type of message in a random group chat.
enum RandomGroupMessageType {
  /// Regular text message
  text,

  /// System message (join/leave notifications, etc.)
  system,

  /// Image message
  image,

  /// Audio/voice message
  audio,

  /// Document file
  document,

  /// Video message
  video,
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

  /// URL to media file (for media messages).
  final String? mediaUrl;

  /// Original filename of uploaded media.
  final String? mediaFileName;

  /// Size of media file in bytes.
  final int? mediaFileSize;

  /// Duration in seconds (for audio/video messages).
  final int? duration;

  /// Thumbnail URL for videos/documents.
  final String? thumbnailUrl;

  /// When the message was sent
  final DateTime sentAt;

  /// Whether this message has been deleted (soft delete).
  final bool isDeleted;

  /// Client-side optimistic ID for deduplication.
  final String? localId;

  /// Message send status (pending, sent, error).
  final GroupMessageStatus status;

  /// Upload progress (0.0 to 1.0) for media uploads.
  final double? uploadProgress;

  /// Error description when status == GroupMessageStatus.error.
  final String? errorReason;

  const RandomGroupMessage({
    required this.id,
    required this.groupId,
    this.senderId,
    this.senderUsername,
    this.senderName,
    this.senderPhotoUrl,
    required this.text,
    required this.type,
    this.mediaUrl,
    this.mediaFileName,
    this.mediaFileSize,
    this.duration,
    this.thumbnailUrl,
    required this.sentAt,
    this.isDeleted = false,
    this.localId,
    this.status = GroupMessageStatus.sent,
    this.uploadProgress,
    this.errorReason,
  });

  /// Check if this is a system message
  bool get isSystemMessage => type == RandomGroupMessageType.system;

  /// Check if this message was sent by a specific user
  bool isSentBy(String userId) => senderId == userId;

  /// Whether this is a media message (non-text, non-system).
  bool get isMediaMessage =>
      type != RandomGroupMessageType.text &&
      type != RandomGroupMessageType.system;

  /// Whether this message can be retried (failed to send).
  bool get canRetry => status == GroupMessageStatus.error;

  /// Whether this message is still pending confirmation.
  bool get isPending => status == GroupMessageStatus.pending;

  RandomGroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? senderUsername,
    String? senderName,
    String? senderPhotoUrl,
    String? text,
    RandomGroupMessageType? type,
    String? mediaUrl,
    String? mediaFileName,
    int? mediaFileSize,
    int? duration,
    String? thumbnailUrl,
    DateTime? sentAt,
    bool? isDeleted,
    String? localId,
    GroupMessageStatus? status,
    double? uploadProgress,
    String? errorReason,
  }) {
    return RandomGroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      senderName: senderName ?? this.senderName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaFileName: mediaFileName ?? this.mediaFileName,
      mediaFileSize: mediaFileSize ?? this.mediaFileSize,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      sentAt: sentAt ?? this.sentAt,
      isDeleted: isDeleted ?? this.isDeleted,
      localId: localId ?? this.localId,
      status: status ?? this.status,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorReason: errorReason ?? this.errorReason,
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
        mediaUrl,
        mediaFileName,
        mediaFileSize,
        duration,
        thumbnailUrl,
        sentAt,
        isDeleted,
        localId,
        status,
        uploadProgress,
        errorReason,
      ];
}
