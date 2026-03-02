import 'dart:async';

import 'package:logger/logger.dart';

import '../domain/entities/message.dart';
import 'chat_service.dart';

/// Callback signature for notifying UI of retry status changes.
typedef RetryStatusCallback = void Function(String localId, MessageStatus status, {String? error});

/// Service for retrying failed messages — inspired by v_chat_sdk's ReSendDaemon.
///
/// Maintains a queue of failed messages and retries them periodically or on demand.
/// Unlike v_chat_sdk's approach (which uses a global singleton with 10-second timers),
/// this uses a per-conversation pattern that integrates cleanly with BLoC.
///
/// Features:
/// - Automatic retry with exponential backoff
/// - Max retry limit (3 attempts)
/// - Manual retry trigger
/// - Retry status callbacks for UI updates
class MessageRetryService {
  final ChatService _chatService;
  final Logger _logger;

  /// Maximum number of automatic retry attempts per message.
  static const int maxRetries = 3;

  /// Base delay between retries (doubles each attempt).
  static const Duration baseRetryDelay = Duration(seconds: 2);

  /// Failed messages waiting for retry, keyed by localId.
  final Map<String, _RetryEntry> _retryQueue = {};

  /// Active retry timers.
  final Map<String, Timer> _retryTimers = {};

  /// Callback for notifying UI of status changes.
  RetryStatusCallback? onStatusChanged;

  MessageRetryService({
    required ChatService chatService,
    Logger? logger,
  })  : _chatService = chatService,
        _logger = logger ?? Logger();

  /// Number of messages in the retry queue.
  int get pendingRetries => _retryQueue.length;

  /// Enqueue a failed text message for retry.
  void enqueueTextMessage({
    required Message message,
    required String? recipientId,
  }) {
    final localId = message.localId ?? message.id;
    final existing = _retryQueue[localId];

    _retryQueue[localId] = _RetryEntry(
      message: message,
      recipientId: recipientId,
      retryCount: existing?.retryCount ?? message.retryCount,
    );

    _scheduleRetry(localId);
  }

  /// Manually trigger a retry for a specific message.
  Future<void> retryMessage(String localId) async {
    final entry = _retryQueue[localId];
    if (entry == null) return;

    // Cancel any existing timer
    _retryTimers[localId]?.cancel();

    await _performRetry(localId, entry);
  }

  /// Remove a message from the retry queue (e.g., user deleted it).
  void removeFromQueue(String localId) {
    _retryQueue.remove(localId);
    _retryTimers[localId]?.cancel();
    _retryTimers.remove(localId);
  }

  /// Clear all pending retries (e.g., on chat close or logout).
  void clearAll() {
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _retryQueue.clear();
  }

  /// Schedule an automatic retry with exponential backoff.
  void _scheduleRetry(String localId) {
    final entry = _retryQueue[localId];
    if (entry == null) return;

    if (entry.retryCount >= maxRetries) {
      _logger.w('Message $localId exceeded max retries (${entry.retryCount})');
      onStatusChanged?.call(localId, MessageStatus.error,
          error: 'Failed after $maxRetries attempts. Tap to retry.');
      return;
    }

    // Exponential backoff: 2s, 4s, 8s
    final delay = baseRetryDelay * (1 << entry.retryCount);
    _logger.d('Scheduling retry for $localId in ${delay.inSeconds}s (attempt ${entry.retryCount + 1})');

    _retryTimers[localId]?.cancel();
    _retryTimers[localId] = Timer(delay, () {
      final currentEntry = _retryQueue[localId];
      if (currentEntry != null) {
        _performRetry(localId, currentEntry);
      }
    });
  }

  /// Perform the actual retry.
  Future<void> _performRetry(String localId, _RetryEntry entry) async {
    onStatusChanged?.call(localId, MessageStatus.sending);

    try {
      final message = entry.message;

      if (message.isMediaMessage) {
        // Media messages can't be retried without the original file
        // Mark as permanent failure
        onStatusChanged?.call(localId, MessageStatus.error,
            error: 'Media upload failed. Please send again.');
        _retryQueue.remove(localId);
        return;
      }

      // Retry text message
      await _chatService.sendMessage(
        conversationId: message.conversationId,
        senderId: message.senderId,
        text: message.text,
        recipientId: entry.recipientId,
        localId: localId,
      );

      // Success — remove from queue
      _logger.i('Retry successful for $localId');
      _retryQueue.remove(localId);
      _retryTimers.remove(localId);
      onStatusChanged?.call(localId, MessageStatus.sent);
    } catch (e) {
      _logger.e('Retry failed for $localId: $e');

      // Increment retry count
      _retryQueue[localId] = entry.copyWith(
        retryCount: entry.retryCount + 1,
      );

      // Schedule next retry (or mark as permanent failure)
      _scheduleRetry(localId);
    }
  }

  /// Dispose all timers.
  void dispose() {
    clearAll();
  }
}

/// Internal entry tracking a message pending retry.
class _RetryEntry {
  final Message message;
  final String? recipientId;
  final int retryCount;

  const _RetryEntry({
    required this.message,
    this.recipientId,
    this.retryCount = 0,
  });

  _RetryEntry copyWith({
    Message? message,
    String? recipientId,
    int? retryCount,
  }) {
    return _RetryEntry(
      message: message ?? this.message,
      recipientId: recipientId ?? this.recipientId,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
