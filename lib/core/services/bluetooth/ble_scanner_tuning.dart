import 'package:flutter/foundation.dart';

import 'rssi_smoothing.dart';

/// Runtime-tunable parameters for stabilizing scan results.
@immutable
class BleScannerTuning {
  final RssiSmoothingSettings rssiSmoothing;

  /// If set, overrides the scan-session enter threshold derived from range mode.
  ///
  /// Enter threshold is the RSSI (dBm) required for a device to become visible.
  final int? enterThresholdOverrideDbm;

  /// If set, overrides the scan-session exit threshold.
  ///
  /// Exit threshold is the RSSI (dBm) below which a visible device becomes hidden.
  final int? exitThresholdOverrideDbm;

  /// Hysteresis delta in dB used when no explicit exit threshold override is set.
  ///
  /// Default: enter - 10dB.
  final int hysteresisDb;

  /// Grace period before a device is considered stale (no observations).
  final Duration staleGracePeriod;

  /// How often the scanner prunes stale devices.
  final Duration staleCleanupInterval;

  const BleScannerTuning({
    this.rssiSmoothing = const RssiSmoothingSettings(),
    this.enterThresholdOverrideDbm,
    this.exitThresholdOverrideDbm,
    this.hysteresisDb = 10,
    this.staleGracePeriod = const Duration(seconds: 25),
    this.staleCleanupInterval = const Duration(seconds: 10),
  }) : assert(hysteresisDb >= 0);

  BleScannerTuning copyWith({
    RssiSmoothingSettings? rssiSmoothing,
    int? enterThresholdOverrideDbm,
    int? exitThresholdOverrideDbm,
    int? hysteresisDb,
    Duration? staleGracePeriod,
    Duration? staleCleanupInterval,
  }) {
    return BleScannerTuning(
      rssiSmoothing: rssiSmoothing ?? this.rssiSmoothing,
      enterThresholdOverrideDbm:
          enterThresholdOverrideDbm ?? this.enterThresholdOverrideDbm,
      exitThresholdOverrideDbm:
          exitThresholdOverrideDbm ?? this.exitThresholdOverrideDbm,
      hysteresisDb: hysteresisDb ?? this.hysteresisDb,
      staleGracePeriod: staleGracePeriod ?? this.staleGracePeriod,
      staleCleanupInterval: staleCleanupInterval ?? this.staleCleanupInterval,
    );
  }
}

/// In-memory runtime override for scanner tuning.
///
/// Intended for debug UI to call without changing scanner internals.
class BleScannerTuningOverrides {
  static BleScannerTuning? _override;

  static BleScannerTuning? get value => _override;

  static void set(BleScannerTuning? tuning) {
    _override = tuning;
  }
}
