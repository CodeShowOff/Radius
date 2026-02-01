import 'package:logger/logger.dart';

import '../domain/entities/random_group_message.dart';

/// Entry in the random group chat cache containing messages and metadata.
class RandomGroupChatCacheEntry {
  final List<RandomGroupMessage> messages;
  final DateTime lastUpdated;
  final DateTime createdAt;
  final bool hasMore;

  RandomGroupChatCacheEntry({
    required this.messages,
    required this.lastUpdated,
    DateTime? createdAt,
    this.hasMore = true,
  }) : createdAt = createdAt ?? lastUpdated;

  RandomGroupChatCacheEntry copyWith({
    List<RandomGroupMessage>? messages,
    DateTime? lastUpdated,
    DateTime? createdAt,
    bool? hasMore,
  }) {
    return RandomGroupChatCacheEntry(
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

/// In-memory cache for random group chat messages.
///
/// Random groups are persistent, so this cache uses standard TTL
/// similar to regular group chats.
class RandomGroupChatCacheService {
  final Logger _logger;

  /// Map of groupId -> cached messages (newest first)
  final Map<String, RandomGroupChatCacheEntry> _cache = {};

  /// LRU access order tracking (most recently accessed at end)
  final List<String> _accessOrder = [];

  /// Maximum number of groups to keep in cache
  static const int maxCachedGroups = 20;

  /// Maximum messages to keep per group
  static const int maxMessagesPerGroup = 100;

  /// Default TTL for cache entries (90 seconds)
  static const Duration defaultTtl = Duration(seconds: 90);

  RandomGroupChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get cached messages for a group.
  /// Returns null if no cache exists.
  RandomGroupChatCacheEntry? getCache(String groupId) {
    _touchForLru(groupId);
    return _cache[groupId];
  }

  /// Check if we have valid (non-expired) cached messages for a group.
  bool hasValidCache(String groupId, {Duration? ttl}) {
    final entry = _cache[groupId];
    if (entry == null || entry.messages.isEmpty) return false;

    // If TTL is provided, check expiration
    if (ttl != null && entry.isExpired(ttl)) {
      _logger.d('Cache expired for random group $groupId');
      return false;
    }
    return true;
  }

  /// Check if we have cached messages for a group (ignores TTL).
  bool hasCache(String groupId) {
    final entry = _cache[groupId];
    return entry != null && entry.messages.isNotEmpty;
  }

  /// Get cached messages for a group (empty list if no cache).
  List<RandomGroupMessage> getMessages(String groupId) {
    _touchForLru(groupId);
    return _cache[groupId]?.messages ?? const [];
  }

  /// Update LRU access order when a group is accessed.
  void _touchForLru(String groupId) {
    _accessOrder.remove(groupId);
    _accessOrder.add(groupId);
  }

  /// Update cache with new messages from Firestore stream.
  void updateCache({
    required String groupId,
    required List<RandomGroupMessage> messages,
    bool? hasMore,
    bool isPreload = false,
  }) {
    final existing = _cache[groupId];
    final now = DateTime.now();

    // Merge with existing paginated messages
    List<RandomGroupMessage> mergedMessages;
    if (existing != null &&
        existing.messages.isNotEmpty &&
        messages.isNotEmpty) {
      final newMessageIds = messages.map((m) => m.id).toSet();
      final oldMessagesNotInNew = existing.messages
          .where((m) => !newMessageIds.contains(m.id))
          .toList();

      if (messages.isNotEmpty && oldMessagesNotInNew.isNotEmpty) {
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
    if (mergedMessages.length > maxMessagesPerGroup) {
      mergedMessages = mergedMessages.sublist(0, maxMessagesPerGroup);
    }

    _cache[groupId] = RandomGroupChatCacheEntry(
      messages: mergedMessages,
      lastUpdated: now,
      createdAt: isPreload ? now : (existing?.createdAt ?? now),
      hasMore: hasMore ?? existing?.hasMore ?? true,
    );

    _touchForLru(groupId);
    _evictOldEntries();

    _logger.d(
      'Cache updated for random group $groupId: ${mergedMessages.length} messages',
    );
  }

  /// Add paginated messages (older messages loaded via "load more").
  void addPaginatedMessages({
    required String groupId,
    required List<RandomGroupMessage> olderMessages,
    required bool hasMore,
  }) {
    final existing = _cache[groupId];
    if (existing == null) {
      _cache[groupId] = RandomGroupChatCacheEntry(
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

    var mergedMessages = [...existing.messages, ...newOlderMessages];

    // Trim to max size
    if (mergedMessages.length > maxMessagesPerGroup) {
      mergedMessages = mergedMessages.sublist(0, maxMessagesPerGroup);
    }

    _cache[groupId] = existing.copyWith(
      messages: mergedMessages,
      lastUpdated: DateTime.now(),
      hasMore: hasMore,
    );

    _logger.d(
      'Added ${newOlderMessages.length} paginated messages to random group $groupId cache',
    );
  }

  /// Evict oldest entries when cache exceeds max size.
  void _evictOldEntries() {
    while (_accessOrder.length > maxCachedGroups) {
      final oldestGroupId = _accessOrder.removeAt(0);
      _cache.remove(oldestGroupId);
      _logger.d('Evicted random group cache for: $oldestGroupId');
    }
  }

  /// Clear cache for a specific group.
  void clearCache(String groupId) {
    _cache.remove(groupId);
    _accessOrder.remove(groupId);
    _logger.d('Cleared cache for random group: $groupId');
  }

  /// Clear all caches.
  void clearAll() {
    _cache.clear();
    _accessOrder.clear();
    _logger.d('Cleared all random group chat caches');
  }
}
