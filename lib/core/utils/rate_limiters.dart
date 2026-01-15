import 'dart:async';

/// Debouncer utility to limit how often a function can be called.
/// 
/// Useful for search inputs, typing indicators, and other
/// frequent user interactions that shouldn't trigger on every keystroke.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 300)});

  /// Run the callback after the delay, cancelling any pending calls.
  void run(void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  /// Cancel any pending callback.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Dispose the debouncer.
  void dispose() {
    cancel();
  }
}

/// Throttler utility to limit how often a function can be called.
/// 
/// Unlike debouncer, throttler ensures the function is called
/// at most once per interval, executing on the leading edge.
class Throttler {
  final Duration interval;
  DateTime? _lastRun;
  Timer? _pendingTimer;

  Throttler({this.interval = const Duration(milliseconds: 300)});

  /// Run the callback if enough time has passed since the last run.
  void run(void Function() callback) {
    final now = DateTime.now();

    if (_lastRun == null || now.difference(_lastRun!) >= interval) {
      _lastRun = now;
      callback();
    } else if (_pendingTimer == null) {
      // Schedule for end of interval
      final remaining = interval - now.difference(_lastRun!);
      _pendingTimer = Timer(remaining, () {
        _lastRun = DateTime.now();
        _pendingTimer = null;
        callback();
      });
    }
  }

  /// Cancel any pending callback.
  void cancel() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  /// Dispose the throttler.
  void dispose() {
    cancel();
  }
}

/// Memoizer for caching expensive function results.
/// 
/// Caches the result of a function call based on its arguments.
/// Results expire after the specified TTL.
class Memoizer<K, V> {
  final Duration ttl;
  final Map<K, _MemoEntry<V>> _cache = {};

  Memoizer({this.ttl = const Duration(minutes: 5)});

  /// Get cached value or compute and cache.
  V call(K key, V Function() compute) {
    final entry = _cache[key];
    
    if (entry != null && !entry.isExpired) {
      return entry.value;
    }

    final value = compute();
    _cache[key] = _MemoEntry(value, DateTime.now().add(ttl));
    return value;
  }

  /// Get cached value or compute async and cache.
  Future<V> callAsync(K key, Future<V> Function() compute) async {
    final entry = _cache[key];
    
    if (entry != null && !entry.isExpired) {
      return entry.value;
    }

    final value = await compute();
    _cache[key] = _MemoEntry(value, DateTime.now().add(ttl));
    return value;
  }

  /// Invalidate a cached value.
  void invalidate(K key) {
    _cache.remove(key);
  }

  /// Clear all cached values.
  void clear() {
    _cache.clear();
  }
}

class _MemoEntry<V> {
  final V value;
  final DateTime expiresAt;

  _MemoEntry(this.value, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
