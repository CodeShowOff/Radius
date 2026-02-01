import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/nearby_group_message.dart';

/// Firestore model for NearbyGroupMessage entity.
///
/// Firestore structure:
/// ```
/// nearby_groups/{groupId}/messages/{messageId}
///   - groupId: string
///   - senderId: string?
///   - senderUsername: string?
///   - senderName: string?
///   - senderPhotoUrl: string?
///   - text: string
///   - type: string ('text' | 'system')
///   - sentAt: timestamp
/// ```
class NearbyGroupMessageModel extends NearbyGroupMessage {
  const NearbyGroupMessageModel({
    required super.id,
    required super.groupId,
    super.senderId,
    super.senderUsername,
    super.senderName,
    super.senderPhotoUrl,
    required super.text,
    required super.type,
    required super.sentAt,
  });

  /// Creates a model from Firestore document snapshot.
  factory NearbyGroupMessageModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return NearbyGroupMessageModel(
      id: doc.id,
      groupId: data['groupId'] as String,
      senderId: data['senderId'] as String?,
      senderUsername: data['senderUsername'] as String?,
      senderName: data['senderName'] as String?,
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String,
      type: _typeFromString(data['type'] as String?),
      sentAt: _parseTimestamp(data['sentAt']),
    );
  }

  /// Creates a model from a map (for stream data).
  factory NearbyGroupMessageModel.fromMap(Map<String, dynamic> data, String id) {
    return NearbyGroupMessageModel(
      id: id,
      groupId: data['groupId'] as String,
      senderId: data['senderId'] as String?,
      senderUsername: data['senderUsername'] as String?,
      senderName: data['senderName'] as String?,
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      text: data['text'] as String,
      type: _typeFromString(data['type'] as String?),
      sentAt: _parseTimestamp(data['sentAt']),
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
  }) {
    return {
      'groupId': groupId,
      'senderId': senderId,
      'senderUsername': senderUsername,
      if (senderName != null) 'senderName': senderName,
      if (senderPhotoUrl != null) 'senderPhotoUrl': senderPhotoUrl,
      'text': text,
      'type': 'text',
      'sentAt': FieldValue.serverTimestamp(),
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
    };
  }

  /// Converts the model to an entity.
  NearbyGroupMessage toEntity() {
    return NearbyGroupMessage(
      id: id,
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: text,
      type: type,
      sentAt: sentAt,
    );
  }

  static NearbyGroupMessageType _typeFromString(String? type) {
    switch (type) {
      case 'text':
        return NearbyGroupMessageType.text;
      case 'system':
        return NearbyGroupMessageType.system;
      default:
        return NearbyGroupMessageType.text;
    }
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
