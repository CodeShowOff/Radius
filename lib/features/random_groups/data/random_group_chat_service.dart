import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/random_group_message.dart';
import 'models/random_group_message_model.dart';

/// Service for managing random group chat messages in Firestore.
///
/// Key behaviors:
/// - Only approved members can send messages (enforced via Firestore rules)
/// - Messages persist with group lifecycle
/// - Supports system messages for join/leave notifications
class RandomGroupChatService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  RandomGroupChatService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  /// Collection reference for group messages.
  CollectionReference<Map<String, dynamic>> _messagesRef(String groupId) {
    return _firestore
        .collection('random_groups')
        .doc(groupId)
        .collection('messages');
  }

  /// Reference to the group document for updating lastMessagePreview.
  DocumentReference<Map<String, dynamic>> _groupRef(String groupId) {
    return _firestore.collection('random_groups').doc(groupId);
  }

  /// Checks if the user is currently a member of the group.
  Future<bool> isMember({
    required String groupId,
    required String userId,
  }) async {
    try {
      final doc = await _groupRef(groupId)
          .collection('members')
          .doc(userId)
          .get();
      return doc.exists;
    } catch (e) {
      _logger.w('Failed to check membership', error: e);
      return false;
    }
  }

  /// Sends a text message to a random group.
  ///
  /// Note: Firestore rules should enforce that only members can write messages.
  Future<RandomGroupMessage> sendMessage({
    required String groupId,
    required String senderId,
    required String senderUsername,
    String? senderName,
    String? senderPhotoUrl,
    required String text,
  }) async {
    _logger.d('Sending message to random group: $groupId');

    // Sanitize and validate message
    final sanitizedText = text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (sanitizedText.isEmpty) {
      throw ArgumentError('Message text cannot be empty');
    }

    if (sanitizedText.length > 2000) {
      throw ArgumentError('Message must be 2000 characters or less');
    }

    final batch = _firestore.batch();

    // Create the message
    final messageRef = _messagesRef(groupId).doc();
    final messageData = RandomGroupMessageModel.toCreateData(
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: sanitizedText,
    );
    batch.set(messageRef, messageData);

    // Update group's lastMessagePreview and lastMessageAt
    batch.update(_groupRef(groupId), {
      'lastMessagePreview': sanitizedText.length > 100
          ? '${sanitizedText.substring(0, 100)}...'
          : sanitizedText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    _logger.d('Message sent: ${messageRef.id}');

    // Return the message with local data
    return RandomGroupMessage(
      id: messageRef.id,
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: sanitizedText,
      type: RandomGroupMessageType.text,
      sentAt: DateTime.now(),
    );
  }

  /// Sends a system message (e.g., "X joined", "X left").
  Future<void> sendSystemMessage({
    required String groupId,
    required String text,
  }) async {
    _logger.d('Sending system message to random group: $groupId');

    final sanitizedText = text.trim();
    if (sanitizedText.isEmpty) {
      _logger.w('Attempted to send empty system message');
      return;
    }

    try {
      final messageData = RandomGroupMessageModel.toSystemMessageData(
        groupId: groupId,
        text: sanitizedText,
      );

      final batch = _firestore.batch();
      final messageRef = _messagesRef(groupId).doc();
      batch.set(messageRef, messageData);
      batch.update(_groupRef(groupId), {
        'lastMessagePreview': sanitizedText.length > 100
            ? '${sanitizedText.substring(0, 100)}...'
            : sanitizedText,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      _logger.d('System message sent successfully');
    } on FirebaseException catch (e) {
      _logger.w('Failed to send system message: ${e.code}');
    }
  }

  /// Stream of messages for a group (newest first, limited for real-time).
  Stream<List<RandomGroupMessage>> watchMessages(String groupId) {
    return _messagesRef(groupId)
        .orderBy('sentAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RandomGroupMessageModel.fromFirestore(doc).toEntity())
          .toList();
    });
  }

  /// Loads older messages for pagination.
  Future<List<RandomGroupMessage>> loadMoreMessages({
    required String groupId,
    required DateTime beforeTimestamp,
    int limit = 50,
  }) async {
    try {
      final query = await _messagesRef(groupId)
          .orderBy('sentAt', descending: true)
          .where('sentAt', isLessThan: Timestamp.fromDate(beforeTimestamp))
          .limit(limit)
          .get();

      return query.docs
          .map((doc) => RandomGroupMessageModel.fromFirestore(doc).toEntity())
          .toList();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error loading more messages', error: e, stackTrace: stack);
      return [];
    }
  }

  /// Deletes a message (only sender can delete their own message).
  Future<void> deleteMessage({
    required String groupId,
    required String messageId,
    required String userId,
  }) async {
    try {
      final messageDoc = await _messagesRef(groupId).doc(messageId).get();
      if (!messageDoc.exists) return;

      final message = RandomGroupMessageModel.fromFirestore(messageDoc);
      if (message.senderId != userId) {
        throw ArgumentError('You can only delete your own messages');
      }

      await _messagesRef(groupId).doc(messageId).delete();
      _logger.d('Deleted message: $messageId');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error deleting message', error: e, stackTrace: stack);
      rethrow;
    }
  }
}
