import 'package:logger/logger.dart';

import '../domain/entities/nearby_group_message.dart';

/// Entry in the nearby group chat cache containing messages and metadata.
class NearbyGroupChatCacheEntry {
  final List<NearbyGroupMessage> messages;
  final DateTime lastUpdated;
  final DateTime createdAt;
  final bool hasMore;

  NearbyGroupChatCacheEntry({
    required this.messages,
    required this.lastUpdated,
    DateTime? createdAt,
    this.hasMore = true,
  }) : createdAt = createdAt ?? lastUpdated;

  NearbyGroupChatCacheEntry copyWith({
    List<NearbyGroupMessage>? messages,
    DateTime? lastUpdated,
    DateTime? createdAt,
    bool? hasMore,
  }) {
    return NearbyGroupChatCacheEntry(
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

/// In-memory cache for nearby group chat messages.
///
/// Nearby groups are temporary by nature, so this cache is more aggressive
/// about eviction and has shorter TTL than regular group chats.
class NearbyGroupChatCacheService {
  final Logger _logger;

  /// Map of groupId -> cached messages (newest first)
  final Map<String, NearbyGroupChatCacheEntry> _cache = {};

  /// LRU access order tracking (most recently accessed at end)
  final List<String> _accessOrder = [];

  /// Maximum number of groups to keep in cache
  static const int maxCachedGroups = 10;

  /// Maximum messages to keep per group
  static const int maxMessagesPerGroup = 100;

  /// Default TTL for cache entries (30 seconds - shorter for nearby groups)
  static const Duration defaultTtl = Duration(seconds: 30);

  NearbyGroupChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get cached messages for a group.
  /// Returns null if no cache exists.
  NearbyGroupChatCacheEntry? getCache(String groupId) {
    _touchForLru(groupId);
    return _cache[groupId];
  }

  /// Check if we have valid (non-expired) cached messages for a group.
  bool hasValidCache(String groupId, {Duration? ttl}) {
    final entry = _cache[groupId];
    if (entry == null || entry.messages.isEmpty) return false;

    // If TTL is provided, check expiration
    if (ttl != null && entry.isExpired(ttl)) {
      _logger.d('Cache expired for nearby group $groupId');
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
  List<NearbyGroupMessage> getMessages(String groupId) {
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
    required List<NearbyGroupMessage> messages,
    bool? hasMore,
  }) {
    final existing = _cache[groupId];
    final now = DateTime.now();

    // Merge with existing messages if any
    List<NearbyGroupMessage> mergedMessages;
    if (existing != null && existing.messages.isNotEmpty && messages.isNotEmpty) {
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

    _cache[groupId] = NearbyGroupChatCacheEntry(
      messages: mergedMessages,
      lastUpdated: now,
      createdAt: existing?.createdAt ?? now,
      hasMore: hasMore ?? existing?.hasMore ?? true,
    );

    _touchForLru(groupId);
    _evictOldEntries();

    _logger.d('Nearby group cache updated for $groupId: ${mergedMessages.length} messages');
  }

  /// Add paginated messages (older messages loaded via "load more").
  void addPaginatedMessages({
    required String groupId,
    required List<NearbyGroupMessage> olderMessages,
    required bool hasMore,
  }) {
    final existing = _cache[groupId];
    if (existing == null) {
      _cache[groupId] = NearbyGroupChatCacheEntry(
        messages: olderMessages,
        lastUpdated: DateTime.now(),
        hasMore: hasMore,
      );
      return;
    }

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

    _logger.d('Added ${newOlderMessages.length} paginated messages for nearby group $groupId');
  }

  /// Evict oldest entries to stay within cache limits.
  void _evictOldEntries() {
    while (_accessOrder.length > maxCachedGroups) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
      _logger.d('Evicted nearby group cache entry: $oldest');
    }
  }

  /// Clear cache for a specific group.
  void clearCache(String groupId) {
    _cache.remove(groupId);
    _accessOrder.remove(groupId);
  }

  /// Clear all cached data.
  void clearAll() {
    _cache.clear();
    _accessOrder.clear();
    _logger.d('Cleared all nearby group chat cache');
  }
}
