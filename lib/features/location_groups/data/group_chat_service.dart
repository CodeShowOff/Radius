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

    // ==================================================================
    // BATCH 1: Message creation + group metadata (critical, must succeed)
    // Separated from member unread updates to prevent a removed member's
    // stale doc from failing the entire batch (including the message).
    // ==================================================================
    final messageBatch = _firestore.batch();

    // Create the message
    final messageRef = _messagesRef(groupId).doc();
    final messageData = GroupMessageModel.toCreateData(
      groupId: groupId,
      senderId: senderId,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: sanitizedText,
    );
    messageBatch.set(messageRef, messageData);

    // Update group's lastActivityAt and preview
    messageBatch.update(_groupRef(groupId), {
      'lastActivityAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': sanitizedText.length > 100 
          ? '${sanitizedText.substring(0, 100)}...' 
          : sanitizedText,
    });

    // Update sender's lastReadAt atomically with the message.
    // NOTE: We intentionally do NOT set unreadCount to 0 here to avoid a
    // race condition where a concurrent message from another user increments
    // the sender's count between the member read and batch commit, and this
    // hard 0 would overwrite it. The stream handler's markGroupAsRead()
    // handles resetting the count safely.
    final senderMemberRef = _groupRef(groupId).collection('members').doc(senderId);
    messageBatch.set(senderMemberRef, {
      'lastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update sender's inverse index to trigger stream refresh
    final senderInverseRef = _firestore
        .collection('users')
        .doc(senderId)
        .collection('group_memberships')
        .doc(groupId);
    messageBatch.set(
      senderInverseRef,
      {'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    await messageBatch.commit();

    // ==================================================================
    // PHASE 2: Update unread counts for other members (fire-and-forget).
    // Failures here are non-critical — the message is already persisted.
    // Uses batches of 200 to stay under Firestore's 500-operation limit
    // (each member needs 2 ops: member update + inverse index update).
    // ==================================================================
    _updateMemberUnreadCounts(groupId, senderId);

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

  /// Fire-and-forget: increment unreadCount for all active members except sender.
  ///
  /// Each member needs 2 operations (member update + inverse index update),
  /// so we process in batches of 200 to stay under Firestore's 500-op limit.
  /// Failures are logged but do not affect message delivery.
  Future<void> _updateMemberUnreadCounts(String groupId, String senderId) async {
    try {
      final membersSnapshot = await _groupRef(groupId)
          .collection('members')
          .where('status', isEqualTo: 'active')
          .get();

      final otherMembers = membersSnapshot.docs.where((doc) {
        final memberUserId = doc.data()['userId'] as String?;
        return memberUserId != null && memberUserId != senderId;
      }).toList();

      if (otherMembers.isEmpty) return;

      // Each member needs 2 operations: member update + inverse index update
      // 200 members × 2 ops = 400 ops per batch (safe under 500 limit)
      const batchLimit = 200;
      for (var i = 0; i < otherMembers.length; i += batchLimit) {
        final batch = _firestore.batch();
        final end = (i + batchLimit).clamp(0, otherMembers.length);
        for (var j = i; j < end; j++) {
          final doc = otherMembers[j];
          final memberUserId = doc.data()['userId'] as String;

          // Increment unread count
          batch.update(doc.reference, {
            'unreadCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Update inverse index to trigger stream refresh
          final inverseIndexRef = _firestore
              .collection('users')
              .doc(memberUserId)
              .collection('group_memberships')
              .doc(groupId);
          batch.set(
            inverseIndexRef,
            {'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        }
        try {
          await batch.commit();
        } catch (e) {
          _logger.w('Failed to update unread counts batch ${i ~/ batchLimit}', error: e);
        }
      }
    } catch (e) {
      _logger.w('Failed to update member unread counts', error: e);
    }
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
  ///
  /// Optimized: when unreadCount is already 0, only updates lastReadAt
  /// (skips the inverse index update since no badge change is needed).
  /// This prevents redundant writes when the stream handler calls this
  /// on every message emission while the chat is open.
  Future<void> markGroupAsRead({
    required String groupId,
    required String userId,
  }) async {
    try {
      final memberRef = _groupRef(groupId).collection('members').doc(userId);
      final memberDoc = await memberRef.get();
      if (!memberDoc.exists) return;

      final data = memberDoc.data();
      final currentUnread = (data?['unreadCount'] as num?)?.toInt() ?? 0;

      if (currentUnread == 0) {
        // Unread is already 0 — only update lastReadAt to advance the
        // "read" pointer (used by getFirstUnreadMessageId).
        // Skip inverse index update since badge hasn't changed.
        await memberRef.set(
          {
            'lastReadAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } else {
        // Reset unread count and update lastReadAt.
        // Use a batch to update both the membership and inverse index.
        // The inverse index update triggers streamUserMemberships to refetch
        // so the badge on the group list page clears.
        final batch = _firestore.batch();

        batch.set(
          memberRef,
          {
            'unreadCount': 0,
            'lastReadAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        final inverseIndexRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('group_memberships')
            .doc(groupId);

        batch.set(
          inverseIndexRef,
          {
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        await batch.commit();
      }
      _logger.d('Marked group $groupId as read for user $userId');
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
        // User never read this group - no divider needed.
        // Returning null avoids pointing to messages that predate the user's join.
        // The unread count badge on the list page already indicates unread messages.
        return null;
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

  /// Gets the unread count for a user in a group from the member document.
  Future<int> getUnreadCount({
    required String groupId,
    required String userId,
  }) async {
    try {
      final memberDoc = await _groupRef(groupId)
          .collection('members')
          .doc(userId)
          .get();

      if (!memberDoc.exists) return 0;

      final data = memberDoc.data();
      return (data?['unreadCount'] as num?)?.toInt() ?? 0;
    } catch (e) {
      _logger.w('Error getting unread count', error: e);
      return 0;
    }
  }
}
