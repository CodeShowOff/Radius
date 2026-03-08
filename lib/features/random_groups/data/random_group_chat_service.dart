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
    String? localId,
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

    // ==================================================================
    // BATCH 1: Message creation + group metadata (critical, must succeed)
    // Separated from member unread updates to prevent a removed member's
    // stale doc from failing the entire batch (including the message).
    // ==================================================================
    final messageBatch = _firestore.batch();

    // Create the message
    final messageRef = _messagesRef(groupId).doc();
    final messageData = RandomGroupMessageModel.toCreateData(
      groupId: groupId,
      senderId: senderId,
      senderUsername: senderUsername,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      text: sanitizedText,
      localId: localId,
    );
    messageBatch.set(messageRef, messageData);

    // Update group's lastMessagePreview and lastMessageAt
    messageBatch.update(_groupRef(groupId), {
      'lastMessagePreview': sanitizedText.length > 100
          ? '${sanitizedText.substring(0, 100)}...'
          : sanitizedText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
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

    await messageBatch.commit();

    // ==================================================================
    // PHASE 2: Update unread counts for other members (fire-and-forget).
    // Failures here are non-critical — the message is already persisted.
    // Uses batches of 450 to stay under Firestore's 500-operation limit.
    // ==================================================================
    _updateMemberUnreadCounts(groupId, senderId);

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
      localId: localId,
    );
  }

  /// Sends a media message to a random group.
  Future<RandomGroupMessage> sendMediaMessage({
    required String groupId,
    required String senderId,
    required String senderUsername,
    String? senderName,
    String? senderPhotoUrl,
    required RandomGroupMessageType type,
    required String mediaUrl,
    String? mediaFileName,
    int? mediaFileSize,
    String text = '',
    int? duration,
    String? thumbnailUrl,
    String? localId,
  }) async {
    _logger.d('Sending media message to random group: $groupId (type: ${type.name})');

    final messageBatch = _firestore.batch();

    final messageRef = _messagesRef(groupId).doc();
    final messageData = RandomGroupMessageModel.toCreateData(
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
      localId: localId,
    );
    messageBatch.set(messageRef, messageData);

    // Build preview based on type
    final preview = switch (type) {
      RandomGroupMessageType.image => '📷 Photo',
      RandomGroupMessageType.audio => '🎤 Voice message',
      RandomGroupMessageType.document => '📄 ${mediaFileName ?? 'Document'}',
      RandomGroupMessageType.video => '🎬 Video',
      _ => text.isNotEmpty ? text : '📎 Media',
    };

    messageBatch.update(_groupRef(groupId), {
      'lastMessagePreview': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    });

    final senderMemberRef = _groupRef(groupId).collection('members').doc(senderId);
    messageBatch.set(senderMemberRef, {
      'lastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await messageBatch.commit();

    _updateMemberUnreadCounts(groupId, senderId);

    _logger.d('Media message sent: ${messageRef.id}');

    return RandomGroupMessage(
      id: messageRef.id,
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
      sentAt: DateTime.now(),
      localId: localId,
    );
  }

  /// Fire-and-forget: increment unreadCount for all members except sender.
  ///
  /// Processes in batches of 450 to stay under Firestore's 500-op limit.
  /// Failures are logged but do not affect message delivery.
  Future<void> _updateMemberUnreadCounts(String groupId, String senderId) async {
    try {
      final membersSnapshot = await _groupRef(groupId)
          .collection('members')
          .get();

      final otherMembers = membersSnapshot.docs.where((doc) {
        final memberUserId = doc.data()['userId'] as String?;
        return memberUserId != null && memberUserId != senderId;
      }).toList();

      if (otherMembers.isEmpty) return;

      // Process in batches of 450 (safe limit under Firestore's 500)
      const batchLimit = 450;
      for (var i = 0; i < otherMembers.length; i += batchLimit) {
        final batch = _firestore.batch();
        final end = (i + batchLimit).clamp(0, otherMembers.length);
        for (var j = i; j < end; j++) {
          batch.update(otherMembers[j].reference, {
            'unreadCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
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
        .where('isDeleted', isEqualTo: false)
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
          .where('isDeleted', isEqualTo: false)
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
          .where('isDeleted', isEqualTo: false)
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
  ///
  /// Optimized: skips the write entirely when unreadCount is already 0.
  /// This prevents triggering the `watchUserUnreadCounts` collection group
  /// listener unnecessarily on every message stream emission while the
  /// chat is open. The `updateLastReadTimestamp()` method should be called
  /// on chat close to ensure lastReadAt stays current.
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
        // Unread is already 0 — skip write entirely.
        // Writing to the member doc would trigger the collection group
        // listener in watchUserUnreadCounts, causing unnecessary state
        // emissions. lastReadAt is updated on chat close instead.
        return;
      }

      // Reset unread count and update lastReadAt.
      await memberRef.set(
        {
          'unreadCount': 0,
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

  /// Gets the ID of the first unread message for a user based on lastReadAt.
  ///
  /// Returns null if:
  /// - No unread messages exist
  /// - User is not a member
  /// - An error occurs (fails silently to avoid blocking chat load)
  ///
  /// Used to:
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
          .limit(50)
          .get();

      // Filter out messages sent by the current user and system messages
      final unreadFromOthers = unreadSnapshot.docs.where((doc) {
        final senderId = doc.data()['senderId'] as String?;
        final type = doc.data()['type'] as String?;
        return senderId != userId && type != 'system';
      }).toList();

      if (unreadFromOthers.isEmpty) return null;
      return unreadFromOthers.first.id;
    } catch (e, stack) {
      _logger.w('Error getting first unread message ID',
          error: e, stackTrace: stack);
      return null; // Fail silently
    }
  }

  /// Updates lastReadAt for a user in a group without touching unreadCount.
  ///
  /// Called on chat close to ensure the "read" pointer is current for the
  /// next session's unread divider positioning (`getFirstUnreadMessageId`).
  /// Separated from `markGroupAsRead` to avoid triggering unnecessary
  /// collection group listener emissions during normal chat flow.
  Future<void> updateLastReadTimestamp({
    required String groupId,
    required String userId,
  }) async {
    try {
      final memberRef = _groupRef(groupId).collection('members').doc(userId);
      await memberRef.set(
        {
          'lastReadAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      _logger.w('Failed to update last read timestamp', error: e);
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
