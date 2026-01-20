import 'package:logger/logger.dart';

import '../domain/entities/group_message.dart';

/// Entry in the group chat cache containing messages and metadata.
class GroupChatCacheEntry {
  final List<GroupMessage> messages;
  final DateTime lastUpdated;
  final bool hasMore;

  const GroupChatCacheEntry({
    required this.messages,
    required this.lastUpdated,
    this.hasMore = true,
  });

  GroupChatCacheEntry copyWith({
    List<GroupMessage>? messages,
    DateTime? lastUpdated,
    bool? hasMore,
  }) {
    return GroupChatCacheEntry(
      messages: messages ?? this.messages,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Global in-memory cache for group chat messages across all groups.
///
/// This service provides WhatsApp/Telegram-level instant chat loading by:
/// 1. Caching messages per group in memory
/// 2. Providing cached data instantly when opening any group
/// 3. Updating cache when Firestore streams emit new data
/// 4. Maintaining cache across navigation (back/forward between groups)
///
/// This eliminates the "loading spinner on every group switch" problem.
class GroupChatCacheService {
  final Logger _logger;

  /// Map of groupId -> cached messages (newest first)
  final Map<String, GroupChatCacheEntry> _cache = {};

  /// Maximum number of groups to keep in cache
  static const int maxCachedGroups = 30;

  /// Maximum messages to keep per group
  static const int maxMessagesPerGroup = 100;

  GroupChatCacheService({Logger? logger}) : _logger = logger ?? Logger();

  /// Get cached messages for a group.
  /// Returns null if no cache exists.
  GroupChatCacheEntry? getCache(String groupId) {
    return _cache[groupId];
  }

  /// Check if we have cached messages for a group.
  bool hasCache(String groupId) {
    final entry = _cache[groupId];
    return entry != null && entry.messages.isNotEmpty;
  }

  /// Get cached messages for a group (empty list if no cache).
  List<GroupMessage> getMessages(String groupId) {
    return _cache[groupId]?.messages ?? const [];
  }

  /// Update cache with new messages from Firestore stream.
  /// This merges the new messages with any older paginated messages.
  void updateCache({
    required String groupId,
    required List<GroupMessage> messages,
    bool? hasMore,
  }) {
    final existing = _cache[groupId];

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

    _cache[groupId] = GroupChatCacheEntry(
      messages: mergedMessages,
      lastUpdated: DateTime.now(),
      hasMore: hasMore ?? existing?.hasMore ?? true,
    );

    // Evict oldest entries if cache is too large
    _evictOldEntries();

    _logger.d(
      'Group cache updated for $groupId: ${mergedMessages.length} messages',
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
    _logger.d('Cleared cache for group $groupId');
  }

  /// Clear all cached data (e.g., on logout).
  void clearAll() {
    _cache.clear();
    _logger.d('Cleared all group chat cache');
  }

  /// Evict oldest entries if cache exceeds max size.
  void _evictOldEntries() {
    if (_cache.length <= maxCachedGroups) return;

    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastUpdated.compareTo(b.value.lastUpdated));

    final toRemove = entries.length - maxCachedGroups;
    for (int i = 0; i < toRemove; i++) {
      _cache.remove(entries[i].key);
    }

    _logger.d('Evicted $toRemove old group cache entries');
  }
}
