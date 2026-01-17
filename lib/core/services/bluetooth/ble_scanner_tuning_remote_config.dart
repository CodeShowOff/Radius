import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'ble_scanner_tuning.dart';
import 'rssi_smoothing.dart';
import '../logging/device_log.dart';

/// Remote Config keys for BLE scanner tuning.
///
/// All keys are optional. If absent or invalid, defaults remain in effect.
class BleScannerRemoteConfigKeys {
  static const String smoothingMode =
      'ble_scanner_smoothing_mode'; // ema|median
  static const String windowSize = 'ble_scanner_rssi_window_size'; // int
  static const String emaAlpha = 'ble_scanner_ema_alpha'; // double

  static const String hysteresisDb = 'ble_scanner_hysteresis_db'; // int
  static const String enterDbm =
      'ble_scanner_enter_threshold_dbm'; // int (optional override)
  static const String exitDbm =
      'ble_scanner_exit_threshold_dbm'; // int (optional override)

  static const String staleGraceMs = 'ble_scanner_stale_grace_ms'; // int
  static const String staleCleanupMs = 'ble_scanner_stale_cleanup_ms'; // int
}

class BleScannerTuningRemoteConfig {
  static Future<BleScannerTuning> fetchAndActivate({
    BleScannerTuning defaults = const BleScannerTuning(),
  }) async {
    try {
      final rc = FirebaseRemoteConfig.instance;

      // Conservative defaults to avoid frequent network calls.
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          minimumFetchInterval: kDebugMode
              ? const Duration(seconds: 0)
              : const Duration(hours: 6),
        ),
      );

      await rc.fetchAndActivate();

      final modeRaw = rc.getString(BleScannerRemoteConfigKeys.smoothingMode);
      final mode = _parseMode(modeRaw) ?? defaults.rssiSmoothing.mode;

      final windowSize = _safeInt(
        rc.getInt(BleScannerRemoteConfigKeys.windowSize),
        defaults.rssiSmoothing.windowSize,
        min: 1,
        max: 20,
      );

      final emaAlpha = _safeDouble(
        rc.getDouble(BleScannerRemoteConfigKeys.emaAlpha),
        defaults.rssiSmoothing.emaAlpha,
        min: 0.05,
        max: 1.0,
      );

      final hysteresisDb = _safeInt(
        rc.getInt(BleScannerRemoteConfigKeys.hysteresisDb),
        defaults.hysteresisDb,
        min: 0,
        max: 40,
      );

      final enterOverride = _readOptionalDbm(
        rc.getInt(BleScannerRemoteConfigKeys.enterDbm),
      );
      final exitOverride = _readOptionalDbm(
        rc.getInt(BleScannerRemoteConfigKeys.exitDbm),
      );

      final staleGraceMs = _safeInt(
        rc.getInt(BleScannerRemoteConfigKeys.staleGraceMs),
        defaults.staleGracePeriod.inMilliseconds,
        min: 1000,
        max: 5 * 60 * 1000,
      );

      final cleanupMs = _safeInt(
        rc.getInt(BleScannerRemoteConfigKeys.staleCleanupMs),
        defaults.staleCleanupInterval.inMilliseconds,
        min: 1000,
        max: 60 * 1000,
      );

      final tuning = defaults.copyWith(
        rssiSmoothing: RssiSmoothingSettings(
          windowSize: windowSize,
          mode: mode,
          emaAlpha: emaAlpha,
        ),
        hysteresisDb: hysteresisDb,
        enterThresholdOverrideDbm: enterOverride,
        exitThresholdOverrideDbm: exitOverride,
        staleGracePeriod: Duration(milliseconds: staleGraceMs),
        staleCleanupInterval: Duration(milliseconds: cleanupMs),
      );

      DeviceLog.instance.info('ble.scan', 'RemoteConfig tuning loaded', data: {
        'mode': mode.name,
        'windowSize': windowSize,
        'emaAlpha': emaAlpha,
        'hysteresisDb': hysteresisDb,
        'enterOverrideDbm': enterOverride,
        'exitOverrideDbm': exitOverride,
        'staleGraceMs': staleGraceMs,
        'cleanupMs': cleanupMs,
      });

      return tuning;
    } catch (e) {
      // Remote Config is optional; fall back to defaults.
      DeviceLog.instance.warning('ble.scan', 'RemoteConfig tuning unavailable',
          data: {'error': e.toString()});
      return defaults;
    }
  }

  static RssiSmoothingMode? _parseMode(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    return switch (v) {
      'ema' => RssiSmoothingMode.ema,
      'median' => RssiSmoothingMode.median,
      _ => null,
    };
  }

  static int _safeInt(int value, int fallback, {int? min, int? max}) {
    var v = value;
    if (min != null && v < min) v = fallback;
    if (max != null && v > max) v = fallback;
    return v;
  }

  static double _safeDouble(double value, double fallback,
      {double? min, double? max}) {
    var v = value;
    if (min != null && v < min) v = fallback;
    if (max != null && v > max) v = fallback;
    return v;
  }

  /// Treats 0 as "unset" (since Remote Config int defaults to 0).
  static int? _readOptionalDbm(int value) {
    if (value == 0) return null;
    return RssiVisibilityTracker.clampDbm(value);
  }
}
