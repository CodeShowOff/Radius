import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/enums/group_message_status.dart';
import '../../domain/entities/random_group_message.dart';

/// Firestore model for RandomGroupMessage entity.
///
/// Firestore structure:
/// ```
/// random_groups/{groupId}/messages/{messageId}
///   - groupId: string
///   - senderId: string?
///   - senderUsername: string?
///   - senderName: string?
///   - senderPhotoUrl: string?
///   - text: string
///   - type: string ('text' | 'system' | 'image' | 'audio' | 'document' | 'video')
///   - mediaUrl: string?
///   - mediaFileName: string?
///   - mediaFileSize: int?
///   - duration: int?
///   - thumbnailUrl: string?
///   - sentAt: timestamp
/// ```
class RandomGroupMessageModel extends RandomGroupMessage {
  const RandomGroupMessageModel({
    required super.id,
    required super.groupId,
    super.senderId,
    super.senderUsername,
    super.senderName,
    super.senderPhotoUrl,
    required super.text,
    required super.type,
    super.mediaUrl,
    super.mediaFileName,
    super.mediaFileSize,
    super.duration,
    super.thumbnailUrl,
    required super.sentAt,
    super.isDeleted,
    super.localId,
    super.status,
  });

  /// Creates a model from Firestore document snapshot.
  factory RandomGroupMessageModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RandomGroupMessageModel(
      id: doc.id,
      groupId: data['groupId'] as String,
      senderId: data['senderId'] as String?,
      senderUsername: data['senderUsername'] as String?,
      senderName: data['senderName'] as String?,
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String,
      type: _typeFromString(data['type'] as String?),
      mediaUrl: data['mediaUrl'] as String?,
      mediaFileName: data['mediaFileName'] as String?,
      mediaFileSize: data['mediaFileSize'] as int?,
      duration: data['duration'] as int?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      sentAt: _parseTimestamp(data['sentAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
      localId: data['localId'] as String?,
      status: GroupMessageStatus.sent, // Firestore messages are confirmed
    );
  }

  /// Creates a model from a map (for stream data).
  factory RandomGroupMessageModel.fromMap(Map<String, dynamic> data, String id) {
    return RandomGroupMessageModel(
      id: id,
      groupId: data['groupId'] as String,
      senderId: data['senderId'] as String?,
      senderUsername: data['senderUsername'] as String?,
      senderName: data['senderName'] as String?,
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String,
      type: _typeFromString(data['type'] as String?),
      mediaUrl: data['mediaUrl'] as String?,
      mediaFileName: data['mediaFileName'] as String?,
      mediaFileSize: data['mediaFileSize'] as int?,
      duration: data['duration'] as int?,
      thumbnailUrl: data['thumbnailUrl'] as String?,
      sentAt: _parseTimestamp(data['sentAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
      localId: data['localId'] as String?,
      status: GroupMessageStatus.sent,
    );
  }

  /// Converts the model to Firestore data for creating a text message.
  static Map<String, dynamic> toCreateData({
    required String groupId,
    required String senderId,
    required String senderUsername,
    String? senderName,
    String? senderPhotoUrl,
    required String text,
    RandomGroupMessageType type = RandomGroupMessageType.text,
    String? mediaUrl,
    String? mediaFileName,
    int? mediaFileSize,
    int? duration,
    String? thumbnailUrl,
    String? localId,
  }) {
    return {
      'groupId': groupId,
      'senderId': senderId,
      'senderUsername': senderUsername,
      if (senderName != null) 'senderName': senderName,
      if (senderPhotoUrl != null) 'senderPhotoUrl': senderPhotoUrl,
      'text': text,
      'type': type.name,
      'mediaUrl': mediaUrl,
      'mediaFileName': mediaFileName,
      'mediaFileSize': mediaFileSize,
      'duration': duration,
      'thumbnailUrl': thumbnailUrl,
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
      if (localId != null) 'localId': localId,
    };
  }

  /// Converts the model to Firestore data for creating a system message.
  static Map<String, dynamic> toSystemMessageData({
    required String groupId,
    required String text,
  }) {
    return {
      'groupId': groupId,
      'senderId': null,
      'senderUsername': null,
      'senderName': null,
      'senderPhotoUrl': null,
      'text': text,
      'type': 'system',
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    };
  }

  /// Converts the model to an entity.
  RandomGroupMessage toEntity() {
    return RandomGroupMessage(
      id: id,
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
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
      status: status,
    );
  }

  static RandomGroupMessageType _typeFromString(String? type) {
    if (type == null) return RandomGroupMessageType.text;
    return RandomGroupMessageType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => RandomGroupMessageType.text,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    } else {
      return DateTime.now();
    }
  }
}
