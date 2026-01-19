import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/group_message.dart';
import 'models/group_message_model.dart';

/// Service for managing group chat messages in Firestore.
class GroupChatService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  GroupChatService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  /// Collection reference for group messages.
  CollectionReference<Map<String, dynamic>> _messagesRef(String groupId) {
    return _firestore
        .collection('location_groups')
        .doc(groupId)
        .collection('messages');
  }

  /// Reference to the group document for updating lastActivityAt.
  DocumentReference<Map<String, dynamic>> _groupRef(String groupId) {
    return _firestore.collection('location_groups').doc(groupId);
  }

  /// Sends a text message to a group.
  Future<GroupMessage> sendMessage({
    required String groupId,
    required String senderId,
    String? senderName,
    String? senderPhotoUrl,
    required String text,
  }) async {
    _logger.d('Sending message to group: $groupId');

    final batch = _firestore.batch();

    // Create the message
    final messageRef = _messagesRef(groupId).doc();
    final messageData = GroupMessageModel.toCreateData(
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: text,
    );
    batch.set(messageRef, messageData);

    // Update group's lastActivityAt
    batch.update(_groupRef(groupId), {
      'lastActivityAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _logger.d('Message sent: ${messageRef.id}');

    // Return the message with local data (timestamp will be resolved on read)
    return GroupMessage(
      id: messageRef.id,
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: text,
      type: GroupMessageType.text,
      sentAt: DateTime.now(),
      status: GroupMessageStatus.sent,
    );
  }

  /// Sends a system message (e.g., "X joined the group").
  Future<void> sendSystemMessage({
    required String groupId,
    required String text,
  }) async {
    _logger.d('Sending system message to group: $groupId');

    final messageData = GroupMessageModel.toSystemMessageData(
      groupId: groupId,
      text: text,
    );

    await _messagesRef(groupId).add(messageData);
  }

  /// Gets a stream of messages for a group (real-time updates).
  Stream<List<GroupMessage>> watchMessages(
    String groupId, {
    int limit = 50,
  }) {
    _logger.d('Watching messages for group: $groupId');

    return _messagesRef(groupId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => GroupMessageModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Gets paginated messages for a group.
  Future<List<GroupMessage>> getMessages(
    String groupId, {
    int limit = 50,
    DateTime? before,
  }) async {
    _logger.d('Getting messages for group: $groupId, before: $before');

    Query<Map<String, dynamic>> query = _messagesRef(groupId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('sentAt', descending: true)
        .limit(limit);

    if (before != null) {
      query = query.where('sentAt', isLessThan: Timestamp.fromDate(before));
    }

    final snapshot = await query.get();

    return snapshot.docs
        .map((doc) => GroupMessageModel.fromFirestore(doc))
        .toList();
  }

  /// Loads older messages for pagination.
  Future<List<GroupMessage>> loadMoreMessages(
    String groupId, {
    required DateTime beforeTimestamp,
    int limit = 30,
  }) async {
    _logger.d('Loading more messages before: $beforeTimestamp');

    final snapshot = await _messagesRef(groupId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('sentAt', descending: true)
        .startAfter([Timestamp.fromDate(beforeTimestamp)])
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => GroupMessageModel.fromFirestore(doc))
        .toList();
  }

  /// Deletes a message (soft delete).
  Future<void> deleteMessage(String groupId, String messageId) async {
    _logger.d('Deleting message: $messageId from group: $groupId');

    await _messagesRef(groupId).doc(messageId).update({
      'isDeleted': true,
    });
  }

  /// Gets a single message by ID.
  Future<GroupMessage?> getMessage(String groupId, String messageId) async {
    final doc = await _messagesRef(groupId).doc(messageId).get();
    if (!doc.exists) return null;
    return GroupMessageModel.fromFirestore(doc);
  }

  /// Gets the total message count for a group.
  Future<int> getMessageCount(String groupId) async {
    final snapshot = await _messagesRef(groupId)
        .where('isDeleted', isEqualTo: false)
        .count()
        .get();
    return snapshot.count ?? 0;
  }
}
