import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/group_message.dart';

/// Firestore model for group messages.
class GroupMessageModel {
  /// Creates a [GroupMessage] from a Firestore document.
  static GroupMessage fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return GroupMessage(
      id: doc.id,
      groupId: data['groupId'] as String? ?? '',
      senderId: data['senderId'] as String? ?? '',
      senderName: data['senderName'] as String?,
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String? ?? '',
      type: _parseMessageType(data['type'] as String?),
      mediaUrl: data['mediaUrl'] as String?,
      sentAt: _parseTimestamp(data['sentAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  /// Converts a [GroupMessage] to Firestore data.
  static Map<String, dynamic> toFirestore(GroupMessage message) {
    return {
      'groupId': message.groupId,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'senderPhotoUrl': message.senderPhotoUrl,
      'text': message.text,
      'type': message.type.name,
      'mediaUrl': message.mediaUrl,
      'sentAt': message.sentAt,
      'isDeleted': message.isDeleted,
    };
  }

  /// Creates Firestore data for a new message (uses server timestamp).
  static Map<String, dynamic> toCreateData({
    required String groupId,
    required String senderId,
    String? senderName,
    String? senderPhotoUrl,
    required String text,
    GroupMessageType type = GroupMessageType.text,
    String? mediaUrl,
  }) {
    return {
      'groupId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'text': text,
      'type': type.name,
      'mediaUrl': mediaUrl,
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    };
  }

  /// Creates a system message (e.g., "X joined the group").
  static Map<String, dynamic> toSystemMessageData({
    required String groupId,
    required String text,
  }) {
    return {
      'groupId': groupId,
      'senderId': 'system',
      'senderName': null,
      'senderPhotoUrl': null,
      'text': text,
      'type': GroupMessageType.system.name,
      'mediaUrl': null,
      'sentAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    };
  }

  static GroupMessageType _parseMessageType(String? type) {
    if (type == null) return GroupMessageType.text;
    return GroupMessageType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => GroupMessageType.text,
    );
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is DateTime) return timestamp;
    return DateTime.now();
  }
}
