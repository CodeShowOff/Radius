import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/random_group_message.dart';
import 'models/random_group_message_model.dart';

/// Service for managing random group chat messages in Firestore.
///
/// This mirrors the location group chat service for consistent behavior.
///
/// Key behaviors:
/// - Only approved members can send messages (enforced via Firestore rules)
/// - Messages persist with group lifecycle
/// - Supports system messages for join/leave notifications
/// - Membership verification before showing content
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

  /// Checks if the user has an active membership in the group.
  ///
  /// This is used to prevent starting message listeners or writes that would
  /// predictably fail with permission-denied / not-found.
  Future<bool> isActiveMember({
    required String groupId,
    required String userId,
  }) async {
    try {
      final doc = await _groupRef(groupId).collection('members').doc(userId).get();
      return doc.exists;
    } catch (e) {
      _logger.w('Failed to check membership', error: e);
      return false;
    }
  }

  /// Sends a text message to a random group.
  ///
  /// SECURITY: Firestore rules enforce membership - no need for client check.
  /// The BLoC already verified membership when opening the chat.
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

    if (sanitizedText.length > 5000) {
      throw ArgumentError('Message must be 5000 characters or less');
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

    // Return the message with local data (timestamp will be resolved on read)
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
  ///
  /// IMPORTANT: Includes retry logic and delay to handle Firestore replication
  /// when called immediately after membership changes.
  Future<void> sendSystemMessage({
    required String groupId,
    required String text,
    int retryCount = 0,
    bool delayBeforeSend = false,
  }) async {
    _logger.d('Sending system message to random group: $groupId (attempt ${retryCount + 1})');

    // CRITICAL: Add delay if requested (e.g., after join to allow replication)
    if (delayBeforeSend && retryCount == 0) {
      _logger.d('Waiting 1s for Firestore replication before sending system message');
      await Future.delayed(const Duration(milliseconds: 1000));
    }

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
      // Handle permission-denied errors with retry
      if (e.code == 'permission-denied' && retryCount < 3) {
        final delayMs = 500 * (retryCount + 1);
        _logger.w(
          'Permission denied sending system message (replication delay). '
          'Retrying in ${delayMs}ms... (attempt ${retryCount + 1}/3)',
        );

        await Future.delayed(Duration(milliseconds: delayMs));

        return sendSystemMessage(
          groupId: groupId,
          text: text,
          retryCount: retryCount + 1,
          delayBeforeSend: false, // Don't delay again on retry
        );
      }

      _logger.e('Failed to send system message after ${retryCount + 1} attempts', error: e);
      // Don't rethrow - system messages are non-critical
    }
  }

  /// Gets a stream of messages for a group (real-time updates).
  Stream<List<RandomGroupMessage>> watchMessages(
    String groupId, {
    int limit = 50,
  }) {
    _logger.d('Watching messages for random group: $groupId');

    return _messagesRef(groupId)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => RandomGroupMessageModel.fromFirestore(doc).toEntity())
          .toList();
    });
  }

  /// Gets a batch of messages for initial load or pagination.
  Future<List<RandomGroupMessage>> getMessages({
    required String groupId,
    int limit = 50,
    DateTime? beforeTimestamp,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _messagesRef(groupId)
          .orderBy('sentAt', descending: true)
          .limit(limit);

      if (beforeTimestamp != null) {
        query = query.startAfter([Timestamp.fromDate(beforeTimestamp)]);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => RandomGroupMessageModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e) {
      _logger.e('Error getting messages', error: e);
      return [];
    }
  }

  /// Loads older messages for pagination.
  Future<List<RandomGroupMessage>> loadMoreMessages({
    required String groupId,
    required DateTime beforeTimestamp,
    int limit = 30,
  }) async {
    _logger.d('Loading more messages before: $beforeTimestamp');

    try {
      final snapshot = await _messagesRef(groupId)
          .orderBy('sentAt', descending: true)
          .startAfter([Timestamp.fromDate(beforeTimestamp)])
          .limit(limit)
          .get();

      return snapshot.docs
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
    _logger.d('Deleting message: $messageId from group: $groupId');

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

  /// Marks a group as read for a user (resets unread count).
  Future<void> markGroupAsRead({
    required String groupId,
    required String userId,
  }) async {
    try {
      final memberRef = _groupRef(groupId).collection('members').doc(userId);
      final memberDoc = await memberRef.get();
      if (!memberDoc.exists) return;

      await memberRef.set(
        {
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      _logger.d('Marked random group $groupId as read for user $userId');
    } catch (e) {
      _logger.w('Failed to mark group as read', error: e);
    }
  }
}
