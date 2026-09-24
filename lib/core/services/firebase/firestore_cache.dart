import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// In-memory cache for Firestore documents with TTL support.
/// 
/// Reduces Firestore reads by caching frequently accessed documents.
/// Supports automatic invalidation based on time-to-live (TTL).
class FirestoreCache {
  final Duration defaultTtl;
  final int maxSize;

  final Map<String, _CacheEntry> _cache = {};
  Timer? _cleanupTimer;

  FirestoreCache({
    this.defaultTtl = const Duration(minutes: 5),
    this.maxSize = 500,
  }) {
    // Run cleanup every minute
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _cleanup(),
    );
  }

  /// Get a cached document or fetch from Firestore.
  Future<DocumentSnapshot<Map<String, dynamic>>?> get(
    DocumentReference<Map<String, dynamic>> ref, {
    Duration? ttl,
    bool forceRefresh = false,
  }) async {
    final key = ref.path;
    final entry = _cache[key];

    // Return cached if valid
    if (!forceRefresh && entry != null && !entry.isExpired) {
      entry.accessCount++;
      return entry.snapshot;
    }

    // Fetch from Firestore
    try {
      final snapshot = await ref.get();
      _put(key, snapshot, ttl ?? defaultTtl);
      return snapshot;
    } catch (e) {
      // Return stale cache on error if available
      if (entry != null) {
        return entry.snapshot;
      }
      rethrow;
    }
  }

  /// Cache a document snapshot.
  void put(
    DocumentReference<Map<String, dynamic>> ref,
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    Duration? ttl,
  }) {
    _put(ref.path, snapshot, ttl ?? defaultTtl);
  }

  /// Invalidate a cached document.
  void invalidate(String path) {
    _cache.remove(path);
  }

  /// Invalidate all documents matching a prefix.
  void invalidatePrefix(String prefix) {
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Clear the entire cache.
  void clear() {
    _cache.clear();
  }

  /// Check if a document is cached and valid.
  bool has(String path) {
    final entry = _cache[path];
    return entry != null && !entry.isExpired;
  }

  void _put(
    String key,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    Duration ttl,
  ) {
    // Evict if at capacity
    if (_cache.length >= maxSize) {
      _evictLeastUsed();
    }

    _cache[key] = _CacheEntry(
      snapshot: snapshot,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  void _cleanup() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
  }

  void _evictLeastUsed() {
    if (_cache.isEmpty) return;

    // Find least accessed entry
    String? leastUsedKey;
    int leastAccess = double.maxFinite.toInt();

    for (final entry in _cache.entries) {
      if (entry.value.accessCount < leastAccess) {
        leastAccess = entry.value.accessCount;
        leastUsedKey = entry.key;
      }
    }

    if (leastUsedKey != null) {
      _cache.remove(leastUsedKey);
    }
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
  }
}

class _CacheEntry {
  final DocumentSnapshot<Map<String, dynamic>> snapshot;
  final DateTime expiresAt;
  int accessCount = 1;

  _CacheEntry({
    required this.snapshot,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
