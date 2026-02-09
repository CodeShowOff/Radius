import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../di/injection.dart';
import '../../features/chat/data/chat_cache_service.dart';
import '../../features/location_groups/data/group_chat_cache_service.dart';
import '../../features/nearby_groups/data/nearby_group_chat_cache_service.dart';
import '../../features/random_groups/data/random_group_chat_cache_service.dart';
import '../services/notifications/notification_service.dart';
import 'logging/device_log.dart';

/// Clears ALL local app data — the programmatic equivalent of
/// Android Settings → Apps → Radius → Storage → Clear Data.
///
/// Call this on sign-out so the next user session starts completely fresh
/// with zero leftover state from the previous account.
class AppDataClearer {
  const AppDataClearer._();

  /// Wipe every local data store. Safe to call multiple times.
  static Future<void> clearAllAppData() async {
    await Future.wait([
      _clearInMemoryCaches(),
      _clearHiveBoxes(),
      _clearImageCache(),
      _clearFileCacheManager(),
      _clearTempDirectory(),
      _clearApplicationDocumentsDirectory(),
      _clearApplicationSupportDirectory(),
      _clearNotifications(),
      _clearDeviceLogs(),
    ]);
  }

  // ── In-memory LRU caches ──────────────────────────────────────────────────

  static Future<void> _clearInMemoryCaches() async {
    if (getIt.isRegistered<ChatCacheService>()) {
      getIt<ChatCacheService>().clearAll();
    }
    if (getIt.isRegistered<GroupChatCacheService>()) {
      getIt<GroupChatCacheService>().clearAll();
    }
    if (getIt.isRegistered<NearbyGroupChatCacheService>()) {
      getIt<NearbyGroupChatCacheService>().clearAll();
    }
    if (getIt.isRegistered<RandomGroupChatCacheService>()) {
      getIt<RandomGroupChatCacheService>().clearAll();
    }
  }

  // ── Hive (all boxes) ─────────────────────────────────────────────────────

  static Future<void> _clearHiveBoxes() async {
    try {
      // Clear all explicitly known boxes
      for (final boxName in _knownBoxNames) {
        try {
          if (Hive.isBoxOpen(boxName)) {
            final box = Hive.box(boxName);
            await box.clear();
            await box.close();
          }
        } catch (_) {
          // Individual box failure shouldn't block the rest.
        }
      }
      
      // Also try to delete all box files from disk
      try {
        await Hive.deleteFromDisk();
      } catch (_) {
        // Ignore if Hive isn't initialized or files are locked
      }
    } catch (_) {
      // Ignore Hive errors during cleanup.
    }
  }

  /// All known Hive box names used in the app.
  static const List<String> _knownBoxNames = [
    'radius_settings',
    'random_chat_cache',
  ];

  // ── Flutter image cache ───────────────────────────────────────────────────

  static Future<void> _clearImageCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  // ── cached_network_image / flutter_cache_manager on-disk cache ───────────

  static Future<void> _clearFileCacheManager() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
  }

  // ── Temp directory ────────────────────────────────────────────────────────

  static Future<void> _clearTempDirectory() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        // Delete contents but not the directory itself.
        await for (final entity in tempDir.list()) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {
            // Skip files that are locked / in use.
          }
        }
      }
    } catch (_) {}
  }

  // ── Application Documents Directory ───────────────────────────────────────

  static Future<void> _clearApplicationDocumentsDirectory() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      if (docsDir.existsSync()) {
        // Delete all contents except system files
        await for (final entity in docsDir.list()) {
          try {
            // Skip system/hidden files
            if (entity.path.contains('/.') || entity.path.contains('\\.')) {
              continue;
            }
            
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {
            // Skip files that are locked / in use.
          }
        }
      }
    } catch (_) {}
  }

  // ── Application Support Directory ─────────────────────────────────────────

  static Future<void> _clearApplicationSupportDirectory() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      if (supportDir.existsSync()) {
        // Delete all contents except system files
        await for (final entity in supportDir.list()) {
          try {
            // Skip system/hidden files
            if (entity.path.contains('/.') || entity.path.contains('\\.')) {
              continue;
            }
            
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {
            // Skip files that are locked / in use.
          }
        }
      }
    } catch (_) {}
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  static Future<void> _clearNotifications() async {
    try {
      if (getIt.isRegistered<NotificationService>()) {
        await getIt<NotificationService>().clearAllNotifications();
      }
    } catch (_) {}
  }

  // ── Device logs ───────────────────────────────────────────────────────────

  static Future<void> _clearDeviceLogs() async {
    try {
      // Only clear if DeviceLog has been initialized
      if (DeviceLog.instance.isInitialized) {
        await DeviceLog.instance.clearAll();
      }
    } catch (_) {}
  }
}
