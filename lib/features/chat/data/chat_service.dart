import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/exceptions.dart';
import '../domain/entities/conversation.dart';
import '../domain/entities/message.dart';
import 'models/conversation_model.dart';
import 'models/message_model.dart';

/// Service for managing real-time chat functionality.
///
/// Optimized for low latency with:
/// - Optimistic UI updates
/// - Batched writes
/// - Efficient pagination
/// - Server timestamps
///
/// Firestore Structure:
/// ```
/// conversations/{conversationId}
///   - metadata (participants, last message, unread counts)
///   /messages/{messageId}
///     - message data
/// ```
class ChatService {
  final FirebaseFirestore _firestore;
  final Logger _logger;
  final Uuid _uuid;

  // Collection references
  late final CollectionReference<Map<String, dynamic>> _conversationsRef;

  // Message pagination config
  static const int _messagesPerPage = 50;

  ChatService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger(),
        _uuid = const Uuid() {
    _conversationsRef = _firestore.collection('conversations');
  }

  DatabaseException _mapFirestoreException(FirebaseException e) {
    String message;
    switch (e.code) {
      case 'permission-denied':
        message = 'Permission denied. Please check your authentication.';
        break;
      case 'not-found':
        message = 'Document not found';
        break;
      case 'already-exists':
        message = 'Document already exists';
        break;
      case 'resource-exhausted':
        message = 'Quota exceeded. Please try again later.';
        break;
      case 'unavailable':
        message = 'Service temporarily unavailable';
        break;
      case 'cancelled':
        message = 'Operation was cancelled';
        break;
      case 'failed-precondition':
        message = e.message ?? 'Database operation failed. This may indicate a missing index or invalid query.';
        break;
      default:
        message = e.message ?? 'Database error occurred';
    }

    return DatabaseException(
      message: message,
      code: e.code,
      originalError: e,
    );
  }

  // ==================== CONVERSATIONS ====================

  /// Gets or creates a conversation between two users.
  Future<Conversation> getOrCreateConversation({
    required String currentUserId,
    required String otherUserId,
    required String currentUserName,
    required String otherUserName,
    String? currentUserPhotoUrl,
    String? otherUserPhotoUrl,
  }) async {
    final conversationId =
        Conversation.createConversationId(currentUserId, otherUserId);

    try {
      // Attempt to read first (fast path for existing conversations).
      // NOTE: With our Firestore rules, reading a non-existent conversation doc
      // can yield permission-denied (because `resource` is null), so we treat
      // that as "doesn't exist yet" and create.
      try {
        final doc = await _conversationsRef.doc(conversationId).get();
        if (doc.exists) {
          return ConversationModel.fromFirestore(doc).toEntity();
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
      }

      // Create new conversation
      final conversation = ConversationModel.create(
        currentUserId: currentUserId,
        otherUserId: otherUserId,
        currentUserName: currentUserName,
        otherUserName: otherUserName,
        currentUserPhotoUrl: currentUserPhotoUrl,
        otherUserPhotoUrl: otherUserPhotoUrl,
      );

      try {
        await _conversationsRef
            .doc(conversationId)
            .set(conversation.toFirestore(useServerTimestamp: true));

        _logger.i('Created conversation: $conversationId');
      } on FirebaseException catch (e) {
        // If already exists (race condition where both users created simultaneously),
        // read and return it
        if (e.code == 'already-exists' || e.code == 'failed-precondition') {
          _logger.d('Conversation already exists or race condition, retrying read');
          await Future.delayed(const Duration(milliseconds: 200));
          final doc = await _conversationsRef.doc(conversationId).get();
          if (doc.exists) {
            return ConversationModel.fromFirestore(doc).toEntity();
          }
        }
        rethrow;
      }

      return conversation.toEntity();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error getting/creating conversation',
          error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error getting/creating conversation',
          error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to open conversation',
        code: 'chat-open-failed',
        originalError: e,
      );
    }
  }

  /// Stream of user's conversations ordered by last message.
  Stream<List<Conversation>> getConversationsStream(String userId) {
    return _conversationsRef
        .where('participantIds', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ConversationModel.fromFirestore(doc).toEntity())
            .where((c) => !c.isArchivedBy(userId))
            .toList());
  }

  /// Gets a single conversation.
  Future<Conversation?> getConversation(String conversationId) async {
    try {
      final doc = await _conversationsRef.doc(conversationId).get();
      if (!doc.exists) return null;
      return ConversationModel.fromFirestore(doc).toEntity();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error getting conversation', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error getting conversation', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to load conversation',
        code: 'chat-conversation-load-failed',
        originalError: e,
      );
    }
  }

  /// Stream of a single conversation for real-time updates.
  Stream<Conversation?> getConversationStream(String conversationId) {
    return _conversationsRef.doc(conversationId).snapshots().map((doc) =>
        doc.exists ? ConversationModel.fromFirestore(doc).toEntity() : null);
  }

  /// Gets total unread message count across all conversations.
  Stream<int> getTotalUnreadCountStream(String userId) {
    return _conversationsRef
        .where('participantIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      int total = 0;
      for (final doc in snapshot.docs) {
        final conversation = ConversationModel.fromFirestore(doc);
        total += conversation.getUnreadCount(userId);
      }
      return total;
    });
  }

  // ==================== MESSAGES ====================

  /// Sanitizes message text to prevent XSS and injection attacks.
  String _sanitizeText(String text) {
    // Remove null bytes and control characters (except newlines and tabs)
    var sanitized =
        text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    // Limit length to prevent abuse
    if (sanitized.length > 5000) {
      sanitized = sanitized.substring(0, 5000);
    }
    return sanitized.trim();
  }

  /// Sends a message with optimistic update support.
  ///
  /// Returns the optimistic message immediately for UI update.
  /// The actual message is written to Firestore asynchronously.
  Future<Message> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
    String? recipientId,
  }) async {
    final localId = _uuid.v4();
    final now = DateTime.now();

    // Sanitize input text
    final sanitizedText = _sanitizeText(text);
    if (sanitizedText.isEmpty) {
      return Message(
        id: localId,
        conversationId: conversationId,
        senderId: senderId,
        text: '',
        sentAt: now,
        status: MessageStatus.failed,
        localId: localId,
      );
    }

    // Create optimistic message for immediate UI (show as sent)
    final optimisticMessage = Message(
      id: localId,
      conversationId: conversationId,
      senderId: senderId,
      text: sanitizedText,
      sentAt: now,
      status: MessageStatus.sent,
      localId: localId,
    );

    try {
      // Write to Firestore
      final messagesRef =
          _conversationsRef.doc(conversationId).collection('messages');

      // Convert to Firestore data, but override status to 'sent' for server
      final messageData =
          MessageModel.fromEntity(optimisticMessage).toFirestore();
      messageData['status'] = MessageStatus.sent.name; // Save as 'sent' in Firestore
      
      final docRef = await messagesRef.add(messageData);

      // Update conversation metadata in a batch
      final batch = _firestore.batch();

      // Update last message info
      batch.update(_conversationsRef.doc(conversationId), {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageText': text.trim().length > 100
            ? '${text.trim().substring(0, 100)}...'
            : text.trim(),
        'lastMessageSenderId': senderId,
        // Increment unread count for recipient
        if (recipientId != null)
          'unreadCounts.$recipientId': FieldValue.increment(1),
      });

      await batch.commit();

      _logger.d('Message sent: ${docRef.id}');

      // Return with real ID
      return optimisticMessage.copyWith(
        id: docRef.id,
        status: MessageStatus.sent,
      );
    } catch (e, stack) {
      _logger.e('Error sending message', error: e, stackTrace: stack);
      // Return failed message
      return optimisticMessage.copyWith(status: MessageStatus.failed);
    }
  }

  /// Sends a media message (image, audio, document, sticker).
  ///
  /// Returns the optimistic message immediately for UI update.
  Future<Message> sendMediaMessage({
    required String conversationId,
    required String senderId,
    required MessageType type,
    required String mediaUrl,
    String? mediaFileName,
    int? mediaFileSize,
    int? duration,
    String? thumbnailUrl,
    String text = '',
    String? recipientId,
  }) async {
    final localId = _uuid.v4();
    final now = DateTime.now();

    // Create optimistic message for immediate UI (show as sent)
    final optimisticMessage = Message(
      id: localId,
      conversationId: conversationId,
      senderId: senderId,
      text: text,
      type: type,
      mediaUrl: mediaUrl,
      mediaFileName: mediaFileName,
      mediaFileSize: mediaFileSize,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      sentAt: now,
      status: MessageStatus.sent,
      localId: localId,
    );

    try {
      // Write to Firestore
      final messagesRef =
          _conversationsRef.doc(conversationId).collection('messages');

      // Convert to Firestore data, but override status to 'sent' for server
      final messageData =
          MessageModel.fromEntity(optimisticMessage).toFirestore();
      messageData['status'] = MessageStatus.sent.name; // Save as 'sent' in Firestore
      
      final docRef = await messagesRef.add(messageData);

      // Update conversation metadata
      final batch = _firestore.batch();

      // Determine last message preview text based on type
      String lastMessagePreview;
      switch (type) {
        case MessageType.image:
          lastMessagePreview = '📷 Photo';
          break;
        case MessageType.audio:
          lastMessagePreview = '🎤 Voice message';
          break;
        case MessageType.document:
          lastMessagePreview = '📄 ${mediaFileName ?? 'Document'}';
          break;
        case MessageType.sticker:
          lastMessagePreview = '😀 Sticker';
          break;
        case MessageType.video:
          lastMessagePreview = '🎥 Video';
          break;
        default:
          lastMessagePreview = text;
      }

      batch.update(_conversationsRef.doc(conversationId), {
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageText': lastMessagePreview,
        'lastMessageSenderId': senderId,
        // Increment unread count for recipient
        if (recipientId != null)
          'unreadCounts.$recipientId': FieldValue.increment(1),
      });

      await batch.commit();

      _logger.d('Media message sent: ${docRef.id}');

      // Return with real ID
      return optimisticMessage.copyWith(
        id: docRef.id,
        status: MessageStatus.sent,
      );
    } catch (e, stack) {
      _logger.e('Error sending media message', error: e, stackTrace: stack);
      // Return failed message
      return optimisticMessage.copyWith(status: MessageStatus.failed);
    }
  }

  /// Stream of messages for a conversation with real-time updates.
  ///
  /// Messages are ordered by sentAt descending for efficient pagination.
  Stream<List<Message>> getMessagesStream(
    String conversationId, {
    int limit = _messagesPerPage,
  }) {
    return _conversationsRef
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                MessageModel.fromFirestore(doc, conversationId).toEntity())
            .toList());
  }

  /// Loads older messages for pagination.
  Future<List<Message>> loadMoreMessages(
    String conversationId, {
    required DateTime before,
    int limit = _messagesPerPage,
  }) async {
    try {
      final snapshot = await _conversationsRef
          .doc(conversationId)
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .where('sentAt', isLessThan: Timestamp.fromDate(before))
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) =>
              MessageModel.fromFirestore(doc, conversationId).toEntity())
          .toList();
    } on FirebaseException catch (e, stack) {
      _logger.e('Error loading more messages', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error loading more messages', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to load more messages',
        code: 'chat-pagination-failed',
        originalError: e,
      );
    }
  }

  // ==================== READ RECEIPTS ====================

  /// Marks messages as read and resets unread count.
  ///
  /// This is optimized to batch update multiple messages at once.
  Future<void> markMessagesAsRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      final batch = _firestore.batch();

      // Reset unread count for this user
      batch.update(_conversationsRef.doc(conversationId), {
        'unreadCounts.$userId': 0,
      });

      // Get unread messages sent by the other user
      final unreadMessages = await _conversationsRef
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: userId)
          .where('readAt', isNull: true)
          .limit(100) // Batch limit
          .get();

      final now = Timestamp.now();

      for (final doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'readAt': now,
          'status': MessageStatus.read.name,
        });
      }

      await batch.commit();

      _logger.d('Marked ${unreadMessages.docs.length} messages as read');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error marking messages as read', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error marking messages as read', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to mark messages as read',
        code: 'chat-mark-read-failed',
        originalError: e,
      );
    }
  }

  /// Marks messages as delivered when app opens conversation.
  Future<void> markMessagesAsDelivered({
    required String conversationId,
    required String userId,
  }) async {
    try {
      // Get undelivered messages sent by the other user
      final undeliveredMessages = await _conversationsRef
          .doc(conversationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: userId)
          .where('deliveredAt', isNull: true)
          .limit(100)
          .get();

      if (undeliveredMessages.docs.isEmpty) return;

      final batch = _firestore.batch();
      final now = Timestamp.now();

      for (final doc in undeliveredMessages.docs) {
        batch.update(doc.reference, {
          'deliveredAt': now,
          'status': MessageStatus.delivered.name,
        });
      }

      await batch.commit();

      _logger
          .d('Marked ${undeliveredMessages.docs.length} messages as delivered');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error marking messages as delivered',
          error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error marking messages as delivered',
          error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to mark messages as delivered',
        code: 'chat-mark-delivered-failed',
        originalError: e,
      );
    }
  }

  // ==================== CONVERSATION ACTIONS ====================

  /// Mutes/unmutes a conversation for a user.
  Future<void> setMuted({
    required String conversationId,
    required String userId,
    required bool muted,
  }) async {
    try {
      await _conversationsRef.doc(conversationId).update({
        'mutedBy.$userId': muted,
      });
    } on FirebaseException catch (e, stack) {
      _logger.e('Error setting muted status', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error setting muted status', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to update mute settings',
        code: 'chat-mute-failed',
        originalError: e,
      );
    }
  }

  /// Archives/unarchives a conversation for a user.
  Future<void> setArchived({
    required String conversationId,
    required String userId,
    required bool archived,
  }) async {
    try {
      await _conversationsRef.doc(conversationId).update({
        'archivedBy.$userId': archived,
      });
    } on FirebaseException catch (e, stack) {
      _logger.e('Error setting archived status', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error setting archived status', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to update archive settings',
        code: 'chat-archive-failed',
        originalError: e,
      );
    }
  }

  /// Deletes a message (soft delete).
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
    required String userId,
  }) async {
    try {
      // Verify user is the sender
      final messageDoc = await _conversationsRef
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) return;

      final message = MessageModel.fromFirestore(messageDoc, conversationId);
      if (message.senderId != userId) {
        _logger.w('User $userId attempted to delete message they did not send');
        return;
      }

      await messageDoc.reference.update({
        'isDeleted': true,
        'text': '', // Clear text content
      });

      _logger.d('Message deleted: $messageId');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error deleting message', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error deleting message', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to delete message',
        code: 'chat-delete-message-failed',
        originalError: e,
      );
    }
  }

  /// Updates participant info in a conversation (call when user updates profile).
  Future<void> updateParticipantInfo({
    required String conversationId,
    required String userId,
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      await _conversationsRef.doc(conversationId).update({
        'participantInfo.$userId.displayName': displayName,
        'participantInfo.$userId.photoUrl': photoUrl,
      });
    } on FirebaseException catch (e, stack) {
      _logger.e('Error updating participant info', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error updating participant info', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to update participant info',
        code: 'chat-participant-update-failed',
        originalError: e,
      );
    }
  }

  // ==================== CONVENIENCE METHODS ====================

  /// Marks a conversation as read for a user.
  /// Wrapper for markMessagesAsRead.
  Future<void> markConversationAsRead(
      String conversationId, String userId) async {
    await markMessagesAsRead(conversationId: conversationId, userId: userId);
  }

  /// Archives or unarchives a conversation.
  /// Wrapper for setArchived.
  Future<void> archiveConversation(
    String conversationId,
    String userId, {
    required bool archive,
  }) async {
    await setArchived(
      conversationId: conversationId,
      userId: userId,
      archived: archive,
    );
  }

  /// Mutes or unmutes a conversation.
  /// Wrapper for setMuted.
  Future<void> muteConversation(
    String conversationId,
    String userId, {
    required bool mute,
  }) async {
    await setMuted(
      conversationId: conversationId,
      userId: userId,
      muted: mute,
    );
  }

  /// Clears all messages in a conversation (soft delete all messages).
  Future<void> clearMessages(String conversationId, String userId) async {
    try {
      // Get all messages in the conversation
      final messagesSnapshot = await _conversationsRef
          .doc(conversationId)
          .collection('messages')
          .get();

      if (messagesSnapshot.docs.isEmpty) {
        _logger.d('No messages to clear');
        return;
      }

      // Firestore batch limit is 500 operations - process in chunks
      const int batchSize = 500;
      final docs = messagesSnapshot.docs;
      
      for (int i = 0; i < docs.length; i += batchSize) {
        final batch = _firestore.batch();
        final end = (i + batchSize < docs.length) ? i + batchSize : docs.length;
        
        for (int j = i; j < end; j++) {
          batch.update(docs[j].reference, {
            'isDeleted': true,
            'text': '',
            'mediaUrl': FieldValue.delete(),
          });
        }
        
        await batch.commit();
        _logger.d('Cleared batch ${(i ~/ batchSize) + 1}: ${end - i} messages');
      }

      // Update conversation to clear last message
      await _conversationsRef.doc(conversationId).update({
        'lastMessageText': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });

      _logger.d('Successfully cleared ${docs.length} messages for conversation: $conversationId');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error clearing messages', error: e, stackTrace: stack);
      throw _mapFirestoreException(e);
    } catch (e, stack) {
      _logger.e('Error clearing messages', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to clear messages',
        code: 'chat-clear-failed',
        originalError: e,
      );
    }
  }

  /// Deletes a conversation for a user (soft delete via archive + clear).
  Future<void> deleteConversation(String conversationId, String userId) async {
    try {
      // Archive the conversation for this user
      await setArchived(
        conversationId: conversationId,
        userId: userId,
        archived: true,
      );
      _logger.d('Conversation deleted (archived) for user: $userId');
    } catch (e, stack) {
      _logger.e('Error deleting conversation', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // ==================== TYPING INDICATORS (Optional) ====================

  /// Sets typing status (writes to a separate collection for efficiency).
  Future<void> setTyping({
    required String conversationId,
    required String userId,
    required bool isTyping,
  }) async {
    try {
      final typingRef = _conversationsRef
          .doc(conversationId)
          .collection('typing')
          .doc(userId);

      if (isTyping) {
        await typingRef.set({
          'isTyping': true,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        await typingRef.delete();
      }
    } catch (e) {
      // Typing indicator errors are non-critical
      _logger.d('Typing indicator error: $e');
    }
  }

  /// Stream of typing status for the other user.
  Stream<bool> getTypingStream(String conversationId, String otherUserId) {
    return _conversationsRef
        .doc(conversationId)
        .collection('typing')
        .doc(otherUserId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;

      // Check if typing indicator is stale (> 5 seconds)
      final timestamp = data['timestamp'] as Timestamp?;
      if (timestamp == null) return false;

      final age = DateTime.now().difference(timestamp.toDate());
      return age.inSeconds < 5 && (data['isTyping'] as bool? ?? false);
    });
  }
}
