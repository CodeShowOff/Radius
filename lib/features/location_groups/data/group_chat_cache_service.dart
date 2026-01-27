import 'package:logger/logger.dart';

import '../domain/entities/group_message.dart';

/// Entry in the group chat cache containing messages and metadata.
class GroupChatCacheEntry {
  final List<GroupMessage> messages;
  final DateTime lastUpdated;
  final DateTime createdAt;
  final bool hasMore;

  GroupChatCacheEntry({
    required this.messages,
    required this.lastUpdated,
    DateTime? createdAt,
    this.hasMore = true,
  }) : createdAt = createdAt ?? lastUpdated;

  GroupChatCacheEntry copyWith({
    List<GroupMessage>? messages,
    DateTime? lastUpdated,
    DateTime? createdAt,
    bool? hasMore,
  }) {
    return GroupChatCacheEntry(
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

/// Global in-memory cache for group chat messages across all groups.
///
/// This service provides WhatsApp/Telegram-level instant chat loading by:
/// 1. Caching messages per group in memory
/// 2. Providing cached data instantly when opening any group
/// 3. Updating cache when Firestore streams emit new data
/// 4. Maintaining cache across navigation (back/forward between groups)
/// 5. TTL-based expiration for preloaded chats (90 seconds)
/// 6. LRU eviction to prevent memory bloat
///
/// This eliminates the "loading spinner on every group switch" problem.
class GroupChatCacheService {
  final Logger _logger;

  /// Map of groupId -> cached messages (newest first)
  final Map<String, GroupChatCacheEntry> _cache = {};

  /// LRU access order tracking (most recently accessed at end)
  final List<String> _accessOrder = [];

  /// Maximum number of groups to keep in cache
  static const int maxCachedGroups = 30;

  /// Maximum messages to keep per group
  static const int maxMessagesPerGroup = 100;

  /// Default TTL for preloaded cache entries (90 seconds)
  /// After this time, cache is considered "stale" and should be refreshed
  static const Duration defaultTtl = Duration(seconds: 90);

  GroupChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get cached messages for a group.
  /// Returns null if no cache exists.
  GroupChatCacheEntry? getCache(String groupId) {
    _touchForLru(groupId);
    return _cache[groupId];
  }

  /// Check if we have valid (non-expired) cached messages for a group.
  bool hasValidCache(String groupId, {Duration? ttl}) {
    final entry = _cache[groupId];
    if (entry == null || entry.messages.isEmpty) return false;
    
    // If TTL is provided, check expiration
    if (ttl != null && entry.isExpired(ttl)) {
      _logger.d('Cache expired for group $groupId');
      return false;
    }
    return true;
  }

  /// Check if we have cached messages for a group (ignores TTL).
  /// Use hasValidCache() if you need TTL-aware checks.
  bool hasCache(String groupId) {
    final entry = _cache[groupId];
    return entry != null && entry.messages.isNotEmpty;
  }

  /// Get cached messages for a group (empty list if no cache).
  List<GroupMessage> getMessages(String groupId) {
    _touchForLru(groupId);
    return _cache[groupId]?.messages ?? const [];
  }

  /// Check if cache entry is expired.
  bool isCacheExpired(String groupId, {Duration ttl = defaultTtl}) {
    final entry = _cache[groupId];
    if (entry == null) return true;
    return entry.isExpired(ttl);
  }

  /// Update LRU access order when a group is accessed.
  void _touchForLru(String groupId) {
    _accessOrder.remove(groupId);
    _accessOrder.add(groupId);
  }

  /// Update cache with new messages from Firestore stream.
  /// This merges the new messages with any older paginated messages.
  void updateCache({
    required String groupId,
    required List<GroupMessage> messages,
    bool? hasMore,
    bool isPreload = false,
  }) {
    final existing = _cache[groupId];
    final now = DateTime.now();

    // If we have existing paginated messages, merge them
    List<GroupMessage> mergedMessages;
    if (existing != null && existing.messages.isNotEmpty && messages.isNotEmpty) {
      // Keep older messages that aren't in the new list
      final newMessageIds = messages.map((m) => m.id).toSet();
      final oldMessagesNotInNew = existing.messages
          .where((m) => !newMessageIds.contains(m.id))
          .toList();

      // Combine: new messages (recent) + old paginated messages (older)
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

    // For preloads, set createdAt to now (TTL starts now)
    // For stream updates, preserve original createdAt (TTL continues)
    _cache[groupId] = GroupChatCacheEntry(
      messages: mergedMessages,
      lastUpdated: now,
      createdAt: isPreload ? now : (existing?.createdAt ?? now),
      hasMore: hasMore ?? existing?.hasMore ?? true,
    );

    // Update LRU access order
    _touchForLru(groupId);

    // Evict oldest entries if cache is too large
    _evictOldEntries();

    _logger.d(
      'Group cache updated for $groupId: ${mergedMessages.length} messages (preload: $isPreload)',
    );
  }

  /// Add paginated messages (older messages loaded via "load more").
  void addPaginatedMessages({
    required String groupId,
    required List<GroupMessage> olderMessages,
    required bool hasMore,
  }) {
    final existing = _cache[groupId];
    if (existing == null) {
      _cache[groupId] = GroupChatCacheEntry(
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

    final trimmedMessages = mergedMessages.length > maxMessagesPerGroup
        ? mergedMessages.sublist(0, maxMessagesPerGroup)
        : mergedMessages;

    _cache[groupId] = existing.copyWith(
      messages: trimmedMessages,
      lastUpdated: DateTime.now(),
      hasMore: hasMore,
    );

    _logger.d(
      'Added ${newOlderMessages.length} paginated messages to group $groupId',
    );
  }

  /// Clear cache for a specific group.
  void clearGroup(String groupId) {
    _cache.remove(groupId);
    _accessOrder.remove(groupId);
    _logger.d('Cleared cache for group $groupId');
  }

  /// Clear all cached data (e.g., on logout).
  void clearAll() {
    _cache.clear();
    _accessOrder.clear();
    _logger.d('Cleared all group chat cache');
  }

  /// Evict least recently used entries if cache exceeds max size.
  /// Uses LRU (Least Recently Used) eviction strategy.
  void _evictOldEntries() {
    if (_cache.length <= maxCachedGroups) return;

    final toRemove = _cache.length - maxCachedGroups;

    // Remove from the front of access order (least recently used)
    for (int i = 0; i < toRemove && _accessOrder.isNotEmpty; i++) {
      final groupId = _accessOrder.removeAt(0);
      _cache.remove(groupId);
    }

    _logger.d('LRU evicted $toRemove old group cache entries');
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
      _logger.d('Evicted ${expiredKeys.length} expired group cache entries');
    }
  }

  /// Get cache statistics for debugging.
  Map<String, dynamic> getCacheStats() {
    return {
      'totalGroups': _cache.length,
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
