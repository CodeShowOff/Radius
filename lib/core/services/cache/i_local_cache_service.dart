/// Local cache service interface using Hive.
/// 
/// Provides local persistence for offline support and performance.
abstract class ILocalCacheService {
  /// Initialize cache storage.
  Future<void> initialize();
  
  /// Get cached value by key.
  T? get<T>(String box, String key);
  
  /// Set value in cache.
  Future<void> put<T>(String box, String key, T value);
  
  /// Delete value from cache.
  Future<void> delete(String box, String key);
  
  /// Clear all values in a box.
  Future<void> clearBox(String box);
  
  /// Get all values from a box.
  List<T> getAll<T>(String box);
  
  /// Check if key exists.
  bool containsKey(String box, String key);
  
  /// Close all boxes.
  Future<void> close();
}
