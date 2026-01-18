import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

/// Lightweight settings store backed by Hive (when available).
///
/// In environments where Hive isn't initialized/opened yet (e.g. some tests),
/// it falls back to an in-memory map.
class AppSettingsStore {
  static const String themeModeKey = 'theme_mode';

  final Box<dynamic>? _box;
  final Map<String, Object?> _memory = <String, Object?>{};

  AppSettingsStore({Box<dynamic>? box}) : _box = box;

  ThemeMode getThemeMode({ThemeMode fallback = ThemeMode.system}) {
    final raw = _read(themeModeKey);
    if (raw is String) {
      switch (raw) {
        case 'system':
          return ThemeMode.system;
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
      }
    }
    return fallback;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };

    await _write(themeModeKey, value);
  }

  Object? _read(String key) {
    try {
      final box = _box;
      if (box != null && box.isOpen) {
        return box.get(key);
      }
    } catch (_) {
      // ignore
    }
    return _memory[key];
  }

  Future<void> _write(String key, Object? value) async {
    try {
      final box = _box;
      if (box != null && box.isOpen) {
        await box.put(key, value);
        return;
      }
    } catch (_) {
      // ignore
    }
    _memory[key] = value;
  }
}
