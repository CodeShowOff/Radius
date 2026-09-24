import 'package:equatable/equatable.dart';

import '../../../../core/enums/group_message_status.dart';

/// Type of group message content.
enum GroupMessageType {
  /// Text message.
  text,

  /// Image message.
  image,

  /// Audio/voice message.
  audio,

  /// Document file.
  document,

  /// Video message.
  video,

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

  /// When the message was sent.
  final DateTime sentAt;

  /// Whether this message has been deleted (soft delete).
  final bool isDeleted;

  /// Local-only: optimistic ID for pending messages.
  final String? localId;

  /// Message send status (pending, sent, error).
  final GroupMessageStatus status;

  /// Upload progress (0.0 to 1.0) for media uploads.
  final double? uploadProgress;

  /// Error description when status == GroupMessageStatus.error.
  final String? errorReason;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.senderName,
    this.senderPhotoUrl,
    required this.text,
    this.type = GroupMessageType.text,
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

  /// Whether this message is from the given user.
  bool isFromUser(String userId) => senderId == userId;

  /// Whether this is a system-generated message.
  bool get isSystemMessage => type == GroupMessageType.system;

  /// Whether this message has media attached.
  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;

  /// Whether this is a media message (non-text, non-system).
  bool get isMediaMessage =>
      type != GroupMessageType.text && type != GroupMessageType.system;

  /// Whether this message can be retried (failed to send).
  bool get canRetry => status == GroupMessageStatus.error;

  /// Whether this message is still pending confirmation.
  bool get isPending => status == GroupMessageStatus.pending;

  GroupMessage copyWith({
    String? id,
    String? groupId,
    String? senderId,
    String? senderName,
    String? senderPhotoUrl,
    String? text,
    GroupMessageType? type,
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
    return GroupMessage(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      senderId: senderId ?? this.senderId,
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
