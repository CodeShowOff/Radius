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
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;
      return (data['status'] as String?) == 'active';
    } catch (e) {
      _logger.w('Failed to check membership', error: e);
      return false;
    }
  }

  /// Sends a text message to a group.
  /// 
  /// SECURITY: Firestore rules enforce membership - no need for client check.
  /// The BLoC already verified membership when opening the chat.
  Future<GroupMessage> sendMessage({
    required String groupId,
    required String senderId,
    String? senderName,
    String? senderPhotoUrl,
    required String text,
  }) async {
    _logger.d('Sending message to group: $groupId');

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
    final messageData = GroupMessageModel.toCreateData(
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: sanitizedText,
    );
    batch.set(messageRef, messageData);

    // Update group's lastActivityAt and preview
    batch.update(_groupRef(groupId), {
      'lastActivityAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': sanitizedText.length > 100 
          ? '${sanitizedText.substring(0, 100)}...' 
          : sanitizedText,
    });

    // Update unread counts for all members
    // Reset sender's unread count and increment for all other active members
    final membersSnapshot = await _groupRef(groupId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .get();

    for (final doc in membersSnapshot.docs) {
      final memberUserId = doc.data()['userId'] as String?;
      if (memberUserId == null) continue;

      if (memberUserId == senderId) {
        // Sender: reset unread count and update lastReadAt
        batch.update(doc.reference, {
          'unreadCount': 0,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Other members: increment unread count
        batch.update(doc.reference, {
          'unreadCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();

    _logger.d('Message sent: ${messageRef.id}');

    // Return the message with local data (timestamp will be resolved on read)
    return GroupMessage(
      id: messageRef.id,
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: sanitizedText,
      type: GroupMessageType.text,
      sentAt: DateTime.now(),
    );
  }

  /// Sends a system message (e.g., "X joined the group").
  /// 
  /// IMPORTANT: Includes retry logic and delay to handle Firestore replication
  /// when called immediately after membership changes.
  Future<void> sendSystemMessage({
    required String groupId,
    required String text,
    int retryCount = 0,
    bool delayBeforeSend = false,
  }) async {
    _logger.d('Sending system message to group: $groupId (attempt ${retryCount + 1})');

    // CRITICAL: Add delay if requested (e.g., after join to allow replication)
    if (delayBeforeSend && retryCount == 0) {
      _logger.d('Waiting 1s for Firestore replication before sending system message');
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    // Validate system message
    final sanitizedText = text.trim();
    if (sanitizedText.isEmpty) {
      _logger.w('Attempted to send empty system message');
      return;
    }

    try {
      final messageData = GroupMessageModel.toSystemMessageData(
        groupId: groupId,
        text: sanitizedText,
      );

      final batch = _firestore.batch();
      final messageRef = _messagesRef(groupId).doc();
      batch.set(messageRef, messageData);
      batch.update(_groupRef(groupId), {
        'lastActivityAt': FieldValue.serverTimestamp(),
        'lastMessagePreview': sanitizedText.length > 100
            ? '${sanitizedText.substring(0, 100)}...'
            : sanitizedText,
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

  /// Streams messages from a group with optional pagination.
  ///
  /// [limit] - Number of messages to load (default 50)
  /// [beforeTimestamp] - Load messages before this timestamp (for pagination)
  Stream<List<GroupMessage>> streamMessages({
    required String groupId,
    int limit = 50,
    DateTime? beforeTimestamp,
  }) {
    Query<Map<String, dynamic>> query = _messagesRef(groupId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('sentAt', descending: true)
        .limit(limit);

    // For pagination: load older messages
    if (beforeTimestamp != null) {
      query = query.startAfter([Timestamp.fromDate(beforeTimestamp)]);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => GroupMessageModel.fromFirestore(doc))
          .toList();
    }).handleError((error, stackTrace) {
      _logger.e('Error streaming messages', error: error);
      throw error;
    });
  }

  /// Gets a batch of messages for initial load or pagination.
  Future<List<GroupMessage>> getMessages({
    required String groupId,
    int limit = 50,
    DateTime? beforeTimestamp,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _messagesRef(groupId)
          .where('isDeleted', isEqualTo: false)
          .orderBy('sentAt', descending: true)
          .limit(limit);

      if (beforeTimestamp != null) {
        query = query.startAfter([Timestamp.fromDate(beforeTimestamp)]);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => GroupMessageModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      _logger.e('Error getting messages', error: e);
      return [];
    }
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

  /// Marks a group as read for a user (resets unread count).
  Future<void> markGroupAsRead({
    required String groupId,
    required String userId,
  }) async {
    try {
      final memberRef = _groupRef(groupId).collection('members').doc(userId);
      final memberDoc = await memberRef.get();
      if (!memberDoc.exists) return;

      // Use set with merge to handle missing fields
      await memberRef.set(
        {
          'unreadCount': 0,
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      _logger.w('Failed to mark group as read', error: e);
    }
  }

  /// Gets the ID of the first unread message for a user based on lastReadAt.
  ///
  /// Returns null if:
  /// - No unread messages exist
  /// - User is not a member
  /// - lastReadAt is not set (return oldest message as first unread)
  /// - An error occurs (fails silently to avoid blocking chat load)
  ///
  /// This is used to:
  /// 1. Scroll to the first unread message when opening group chat
  /// 2. Show "Unread messages" divider above this message
  Future<String?> getFirstUnreadMessageId({
    required String groupId,
    required String userId,
  }) async {
    try {
      // Get user's membership to find lastReadAt
      final memberDoc = await _groupRef(groupId)
          .collection('members')
          .doc(userId)
          .get();

      if (!memberDoc.exists) return null;

      final data = memberDoc.data();
      final lastReadAt = data?['lastReadAt'];

      if (lastReadAt == null) {
        // User never read this group - return earliest message
        final firstMessageSnapshot = await _messagesRef(groupId)
            .where('isDeleted', isEqualTo: false)
            .orderBy('sentAt', descending: false)
            .limit(1)
            .get();

        if (firstMessageSnapshot.docs.isEmpty) return null;
        return firstMessageSnapshot.docs.first.id;
      }

      final lastReadTimestamp = lastReadAt as Timestamp;

      // Find the first message AFTER lastReadAt that was NOT sent by this user
      final unreadSnapshot = await _messagesRef(groupId)
          .where('isDeleted', isEqualTo: false)
          .where('sentAt', isGreaterThan: lastReadTimestamp)
          .orderBy('sentAt', descending: false)
          .limit(50) // Reasonable limit
          .get();

      // Filter out messages sent by the current user (and system messages)
      final unreadFromOthers = unreadSnapshot.docs.where((doc) {
        final senderId = doc.data()['senderId'] as String?;
        final isSystem = doc.data()['isSystemMessage'] as bool? ?? false;
        return senderId != userId && !isSystem;
      }).toList();

      if (unreadFromOthers.isEmpty) return null;
      return unreadFromOthers.first.id;
    } catch (e, stack) {
      _logger.w('Error getting first unread message ID', error: e, stackTrace: stack);
      return null; // Fail silently
    }
  }
}
