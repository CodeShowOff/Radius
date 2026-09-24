import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../di/injection.dart';

import '../services/notifications/notification_service.dart';
import 'logging/device_log.dart';

/// Clears ALL local app data â€” the programmatic equivalent of
/// Android Settings → Apps → Radius → Storage → Clear Data.
///
/// Call this on sign-out so the next user session starts completely fresh
/// with zero leftover state from the previous account.
class AppDataClearer {
  const AppDataClearer._();

  /// Wipe every local data store. Safe to call multiple times.
  static Future<void> clearAllAppData() async {
    // â”€â”€ Phase 1: Clear caches that own SQLite / file handles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // These must complete BEFORE we delete directories, otherwise deleting
    // the underlying DB file while flutter_cache_manager still has it open
    // triggers SQLITE_READONLY_DBMOVED (code 1032).
    await Future.wait([
      _clearInMemoryCaches(),
      _clearFileCacheManager(),
      _clearImageCache(),
      _clearNotifications(),
      _clearDeviceLogs(),
    ]);

    // â”€â”€ Phase 2: Hive boxes (close first, then delete files) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    await _clearHiveBoxes();

    // â”€â”€ Phase 3: Delete directories (safe now â€” no open handles) â”€â”€â”€â”€â”€â”€â”€â”€
    await Future.wait([
      _clearTempDirectory(),
      _clearApplicationDocumentsDirectory(),
      _clearApplicationSupportDirectory(),
    ]);

    // â”€â”€ Phase 4: Re-initialize Hive so subsequent box opens don't crash
    // with PathNotFoundException (the directories were just deleted). â”€â”€â”€â”€â”€
    try {
      await Hive.initFlutter();
    } catch (_) {
      // Best-effort: Hive re-init may fail if Flutter engine is shutting down
    }
  }

  // â”€â”€ In-memory LRU caches â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> _clearInMemoryCaches() async {
    // No legacy custom chat caches to clear.
  }

  // â”€â”€ Hive (all boxes) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Flutter image cache â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> _clearImageCache() async {
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  // â”€â”€ cached_network_image / flutter_cache_manager on-disk cache â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> _clearFileCacheManager() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
  }

  // â”€â”€ Temp directory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Application Documents Directory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Application Support Directory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> _clearApplicationSupportDirectory() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      if (supportDir.existsSync()) {
        // Delete all contents except system files and the cache manager's
        // SQLite database (libCachedImageData.db*). That DB is already
        // emptied by DefaultCacheManager().emptyCache() in Phase 1; deleting
        // the file here while the connection is still open causes
        // SQLITE_READONLY_DBMOVED (code 1032).
        await for (final entity in supportDir.list()) {
          try {
            // Skip system/hidden files
            if (entity.path.contains('/.') || entity.path.contains('\\.')) {
              continue;
            }

            // Skip the cache manager's SQLite database (still open)
            final name = entity.uri.pathSegments.last;
            if (name.startsWith('libCachedImageData')) {
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

  // â”€â”€ Notifications â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> _clearNotifications() async {
    try {
      if (getIt.isRegistered<NotificationService>()) {
        await getIt<NotificationService>().clearAllNotifications();
      }
    } catch (_) {}
  }

  // â”€â”€ Device logs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  static Future<void> _clearDeviceLogs() async {
    try {
      // Only clear if DeviceLog has been initialized
      if (DeviceLog.instance.isInitialized) {
        await DeviceLog.instance.clearAll();
      }
    } catch (_) {}
  }
}
