import 'package:hive/hive.dart';

/// Stores local Video Chat preferences (age verification, headphones advisory).
///
/// Backed by Hive for persistence. Falls back to in-memory map when
/// Hive isn't available (tests / early bootstrap).
class VideoChatSettingsService {
  static const String _boxName = 'video_chat_settings';
  static const String _ageVerifiedKey = 'age_verified';
  static const String _headphonesAdvisoryDismissedKey = 'headphones_dismissed';

  Box<dynamic>? _box;
  final Map<String, Object?> _memory = {};

  /// Opens the Hive box. Call during app bootstrap.
  Future<void> init() async {
    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box(_boxName);
      } else {
        _box = await Hive.openBox(_boxName);
      }
    } catch (e) {
      // Hive may not be initialized in some environments; fall back to memory.
      // ignore: avoid_print
      print('VideoChatSettingsService: Hive init failed, using memory fallback: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Age Verification
  // ════════════════════════════════════════════════════════════════════

  /// Whether the user has confirmed they are 18+.
  bool get isAgeVerified {
    final val = _read(_ageVerifiedKey);
    return val is bool && val;
  }

  /// Marks the user as having confirmed 18+ age requirement.
  Future<void> setAgeVerified() async {
    await _write(_ageVerifiedKey, true);
  }

  // ════════════════════════════════════════════════════════════════════
  //  Headphones Advisory
  // ════════════════════════════════════════════════════════════════════

  /// Whether the user has permanently dismissed the headphones advisory.
  bool get isHeadphonesAdvisoryDismissed {
    final val = _read(_headphonesAdvisoryDismissedKey);
    return val is bool && val;
  }

  /// Marks the headphones advisory as permanently dismissed.
  Future<void> dismissHeadphonesAdvisory() async {
    await _write(_headphonesAdvisoryDismissedKey, true);
  }

  // ════════════════════════════════════════════════════════════════════
  //  Internal Helpers
  // ════════════════════════════════════════════════════════════════════

  Object? _read(String key) {
    if (_box != null && _box!.isOpen) return _box!.get(key);
    return _memory[key];
  }

  Future<void> _write(String key, Object value) async {
    _memory[key] = value;
    if (_box != null && _box!.isOpen) {
      await _box!.put(key, value);
    }
  }
}
