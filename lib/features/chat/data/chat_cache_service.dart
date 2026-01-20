import 'package:logger/logger.dart';

import '../domain/entities/message.dart';

/// Entry in the chat cache containing messages and metadata.
class ChatCacheEntry {
  final List<Message> messages;
  final DateTime lastUpdated;
  final bool hasMore;

  const ChatCacheEntry({
    required this.messages,
    required this.lastUpdated,
    this.hasMore = true,
  });

  ChatCacheEntry copyWith({
    List<Message>? messages,
    DateTime? lastUpdated,
    bool? hasMore,
  }) {
    return ChatCacheEntry(
      messages: messages ?? this.messages,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Global in-memory cache for chat messages across all conversations.
///
/// This service provides WhatsApp/Telegram-level instant chat loading by:
/// 1. Caching messages per conversation in memory
/// 2. Providing cached data instantly when opening any conversation
/// 3. Updating cache when Firestore streams emit new data
/// 4. Maintaining cache across navigation (back/forward between chats)
///
/// This eliminates the "loading spinner on every chat switch" problem.
class ChatCacheService {
  final Logger _logger;

  /// Map of conversationId -> cached messages (newest first)
  final Map<String, ChatCacheEntry> _cache = {};

  /// Maximum number of conversations to keep in cache
  static const int maxCachedConversations = 50;

  /// Maximum messages to keep per conversation
  static const int maxMessagesPerConversation = 100;

  ChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get cached messages for a conversation.
  /// Returns null if no cache exists.
  ChatCacheEntry? getCache(String conversationId) {
    return _cache[conversationId];
  }

  /// Check if we have cached messages for a conversation.
  bool hasCache(String conversationId) {
    final entry = _cache[conversationId];
    return entry != null && entry.messages.isNotEmpty;
  }

  /// Get cached messages for a conversation (empty list if no cache).
  List<Message> getMessages(String conversationId) {
    return _cache[conversationId]?.messages ?? const [];
  }

  /// Update cache with new messages from Firestore stream.
  /// This merges the new messages with any older paginated messages.
  void updateCache({
    required String conversationId,
    required List<Message> messages,
    bool? hasMore,
  }) {
    final existing = _cache[conversationId];

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

    _cache[conversationId] = ChatCacheEntry(
      messages: mergedMessages,
      lastUpdated: DateTime.now(),
      hasMore: hasMore ?? existing?.hasMore ?? true,
    );

    // Evict oldest entries if cache is too large
    _evictOldEntries();

    _logger.d(
      'Cache updated for $conversationId: ${mergedMessages.length} messages',
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

  /// Clear cache for a specific conversation.
  void clearConversation(String conversationId) {
    _cache.remove(conversationId);
    _logger.d('Cleared cache for $conversationId');
  }

  /// Clear all cached data (e.g., on logout).
  void clearAll() {
    _cache.clear();
    _logger.d('Cleared all chat cache');
  }

  /// Evict oldest entries if cache exceeds max size.
  void _evictOldEntries() {
    if (_cache.length <= maxCachedConversations) return;

    // Sort by last updated and remove oldest
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastUpdated.compareTo(b.value.lastUpdated));

    final toRemove = entries.length - maxCachedConversations;
    for (int i = 0; i < toRemove; i++) {
      _cache.remove(entries[i].key);
    }

    _logger.d('Evicted $toRemove old cache entries');
  }
}
