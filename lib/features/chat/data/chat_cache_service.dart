import 'package:logger/logger.dart';

import '../domain/entities/message.dart';

/// Entry in the chat cache containing messages and metadata.
class ChatCacheEntry {
  final List<Message> messages;
  final DateTime lastUpdated;
  final DateTime createdAt;
  final bool hasMore;

  ChatCacheEntry({
    required this.messages,
    required this.lastUpdated,
    DateTime? createdAt,
    this.hasMore = true,
  }) : createdAt = createdAt ?? lastUpdated;

  ChatCacheEntry copyWith({
    List<Message>? messages,
    DateTime? lastUpdated,
    DateTime? createdAt,
    bool? hasMore,
  }) {
    return ChatCacheEntry(
      messages: messages ?? this.messages,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      createdAt: createdAt ?? this.createdAt,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  /// Check if this cache entry has expired based on TTL.
  bool isExpired(Duration ttl) {
    return DateTime.now().difference(createdAt) > ttl;
  }
}

/// Global in-memory cache for chat messages across all conversations.
///
/// This service provides WhatsApp/Telegram-level instant chat loading by:
/// 1. Caching messages per conversation in memory
/// 2. Providing cached data instantly when opening any conversation
/// 3. Updating cache when Firestore streams emit new data
/// 4. Maintaining cache across navigation (back/forward between chats)
/// 5. TTL-based expiration for preloaded chats (90 seconds)
/// 6. LRU eviction to prevent memory bloat
///
/// This eliminates the "loading spinner on every chat switch" problem.
class ChatCacheService {
  final Logger _logger;

  /// Map of conversationId -> cached messages (newest first)
  final Map<String, ChatCacheEntry> _cache = {};

  /// Map of conversationId -> pending messages that haven't been confirmed.
  /// This persists across screen rebuilds so pending/error messages survive
  /// navigation. Mirrors v_chat_sdk's local DB persistence for pending messages.
  final Map<String, Map<String, Message>> _pendingMessages = {};

  /// LRU access order tracking (most recently accessed at end)
  final List<String> _accessOrder = [];

  /// Maximum number of conversations to keep in cache
  static const int maxCachedConversations = 50;

  /// Maximum messages to keep per conversation
  static const int maxMessagesPerConversation = 100;

  /// Default TTL for preloaded cache entries (90 seconds)
  /// After this time, cache is considered "stale" and should be refreshed
  static const Duration defaultTtl = Duration(seconds: 90);

  ChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get cached messages for a conversation.
  /// Returns null if no cache exists.
  ChatCacheEntry? getCache(String conversationId) {
    _touchForLru(conversationId);
    return _cache[conversationId];
  }

  /// Check if we have valid (non-expired) cached messages for a conversation.
  bool hasValidCache(String conversationId, {Duration? ttl}) {
    final entry = _cache[conversationId];
    if (entry == null || entry.messages.isEmpty) return false;
    
    // If TTL is provided, check expiration
    if (ttl != null && entry.isExpired(ttl)) {
      _logger.d('Cache expired for $conversationId');
      return false;
    }
    return true;
  }

  /// Check if we have cached messages for a conversation (ignores TTL).
  /// Use hasValidCache() if you need TTL-aware checks.
  bool hasCache(String conversationId) {
    final entry = _cache[conversationId];
    return entry != null && entry.messages.isNotEmpty;
  }

  /// Get cached messages for a conversation (empty list if no cache).
  List<Message> getMessages(String conversationId) {
    _touchForLru(conversationId);
    return _cache[conversationId]?.messages ?? const [];
  }

  /// Check if cache entry is expired.
  bool isCacheExpired(String conversationId, {Duration ttl = defaultTtl}) {
    final entry = _cache[conversationId];
    if (entry == null) return true;
    return entry.isExpired(ttl);
  }

  /// Update LRU access order when a conversation is accessed.
  void _touchForLru(String conversationId) {
    _accessOrder.remove(conversationId);
    _accessOrder.add(conversationId);
  }

  /// Update cache with new messages from Firestore stream.
  /// This merges the new messages with any older paginated messages.
  void updateCache({
    required String conversationId,
    required List<Message> messages,
    bool? hasMore,
    bool isPreload = false,
  }) {
    final existing = _cache[conversationId];
    final now = DateTime.now();

    // If we have existing paginated messages, merge them
    List<Message> mergedMessages;
    if (existing != null && existing.messages.isNotEmpty && messages.isNotEmpty) {
      // Keep older messages that aren't in the new list
      // New messages come from the real-time stream (recent messages)
      // Old messages come from pagination (older messages)
      final newMessageIds = messages.map((m) => m.id).toSet();
      final oldMessagesNotInNew = existing.messages
          .where((m) => !newMessageIds.contains(m.id))
          .toList();

      // Combine: new messages (recent) + old paginated messages (older)
      // Messages should be newest first
      if (messages.isNotEmpty && oldMessagesNotInNew.isNotEmpty) {
        // Only keep old messages that are actually older than the newest in new list
        final oldestNewMessage = messages.last;
        final olderMessages = oldMessagesNotInNew
            .where((m) => m.sentAt.isBefore(oldestNewMessage.sentAt))
            .toList();
        mergedMessages = [...messages, ...olderMessages];
      } else {
        mergedMessages = messages;
      }
    } else {
      mergedMessages = messages;
    }

    // Trim to max size
    if (mergedMessages.length > maxMessagesPerConversation) {
      mergedMessages = mergedMessages.sublist(0, maxMessagesPerConversation);
    }

    // For preloads, set createdAt to now (TTL starts now)
    // For stream updates, preserve original createdAt (TTL continues)
    _cache[conversationId] = ChatCacheEntry(
      messages: mergedMessages,
      lastUpdated: now,
      createdAt: isPreload ? now : (existing?.createdAt ?? now),
      hasMore: hasMore ?? existing?.hasMore ?? true,
    );

    // Update LRU access order
    _touchForLru(conversationId);

    // Evict oldest entries if cache is too large
    _evictOldEntries();

    _logger.d(
      'Cache updated for $conversationId: ${mergedMessages.length} messages (preload: $isPreload)',
    );
  }

  /// Add paginated messages (older messages loaded via "load more").
  void addPaginatedMessages({
    required String conversationId,
    required List<Message> olderMessages,
    required bool hasMore,
  }) {
    final existing = _cache[conversationId];
    if (existing == null) {
      // No existing cache, just store the paginated messages
      _cache[conversationId] = ChatCacheEntry(
        messages: olderMessages,
        lastUpdated: DateTime.now(),
        hasMore: hasMore,
      );
      return;
    }

    // Merge with existing messages
    final existingIds = existing.messages.map((m) => m.id).toSet();
    final newOlderMessages = olderMessages
        .where((m) => !existingIds.contains(m.id))
        .toList();

    final mergedMessages = [...existing.messages, ...newOlderMessages];

    // Trim to max size
    final trimmedMessages = mergedMessages.length > maxMessagesPerConversation
        ? mergedMessages.sublist(0, maxMessagesPerConversation)
        : mergedMessages;

    _cache[conversationId] = existing.copyWith(
      messages: trimmedMessages,
      lastUpdated: DateTime.now(),
      hasMore: hasMore,
    );

    _logger.d(
      'Added ${newOlderMessages.length} paginated messages to $conversationId',
    );
  }

  // ==================== PENDING MESSAGE CACHE ====================

  /// Save pending messages for a conversation.
  /// Called by ChatBloc on close() to persist pending/error messages.
  void savePendingMessages(String conversationId, Map<String, Message> pending) {
    if (pending.isEmpty) {
      _pendingMessages.remove(conversationId);
    } else {
      _pendingMessages[conversationId] = Map.from(pending);
    }
  }

  /// Get cached pending messages for a conversation.
  /// Returns empty map if none exist.
  Map<String, Message> getPendingMessages(String conversationId) {
    return Map.from(_pendingMessages[conversationId] ?? {});
  }

  /// Recover stale pending messages (v_chat_sdk `prepareMessages` pattern).
  /// Any message stuck in `sending` or `pending` status is transitioned to
  /// `error` so the user can see and retry them. This handles the case where
  /// the app was killed mid-send.
  Map<String, Message> recoverPendingMessages(String conversationId) {
    final pending = _pendingMessages[conversationId];
    if (pending == null || pending.isEmpty) return {};

    final recovered = <String, Message>{};
    for (final entry in pending.entries) {
      final msg = entry.value;
      if (msg.status == MessageStatus.sending ||
          msg.status == MessageStatus.pending) {
        // Mark stale sending/pending as error for retry
        recovered[entry.key] = msg.copyWith(
          status: MessageStatus.error,
          errorReason: 'Message was interrupted. Tap to retry.',
        );
      } else if (msg.status == MessageStatus.error) {
        // Keep error messages as-is for retry
        recovered[entry.key] = msg;
      }
      // Skip sent/delivered/seen — those are confirmed
    }

    // Update the cache with recovered state
    if (recovered.isNotEmpty) {
      _pendingMessages[conversationId] = recovered;
      _logger.i('Recovered ${recovered.length} pending messages for $conversationId');
    } else {
      _pendingMessages.remove(conversationId);
    }

    return recovered;
  }

  /// Clear pending messages for a conversation (called after all confirmed).
  void clearPendingMessages(String conversationId) {
    _pendingMessages.remove(conversationId);
  }

  /// Clear cache for a specific conversation.
  void clearConversation(String conversationId) {
    _cache.remove(conversationId);
    _pendingMessages.remove(conversationId);
    _accessOrder.remove(conversationId);
    _logger.d('Cleared cache for $conversationId');
  }

  /// Clear all cached data (e.g., on logout).
  void clearAll() {
    _cache.clear();
    _pendingMessages.clear();
    _accessOrder.clear();
    _logger.d('Cleared all chat cache');
  }

  /// Evict least recently used entries if cache exceeds max size.
  /// Uses LRU (Least Recently Used) eviction strategy.
  void _evictOldEntries() {
    if (_cache.length <= maxCachedConversations) return;

    final toRemove = _cache.length - maxCachedConversations;
    
    // Remove from the front of access order (least recently used)
    for (int i = 0; i < toRemove && _accessOrder.isNotEmpty; i++) {
      final conversationId = _accessOrder.removeAt(0);
      _cache.remove(conversationId);
    }

    _logger.d('LRU evicted $toRemove old cache entries');
  }

  /// Evict expired entries based on TTL.
  void evictExpired({Duration ttl = defaultTtl}) {
    final expiredKeys = _cache.entries
        .where((e) => e.value.isExpired(ttl))
        .map((e) => e.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }

    if (expiredKeys.isNotEmpty) {
      _logger.d('Evicted ${expiredKeys.length} expired cache entries');
    }
  }

  /// Get cache statistics for debugging.
  Map<String, dynamic> getCacheStats() {
    return {
      'totalConversations': _cache.length,
      'totalMessages': _cache.values.fold<int>(0, (sum, e) => sum + e.messages.length),
      'oldestEntry': _cache.values.isEmpty
          ? null
          : _cache.values.map((e) => e.createdAt).reduce((a, b) => a.isBefore(b) ? a : b).toIso8601String(),
      'newestEntry': _cache.values.isEmpty
          ? null
          : _cache.values.map((e) => e.createdAt).reduce((a, b) => a.isAfter(b) ? a : b).toIso8601String(),
    };
  }
}
