import 'dart:math' as math;

/// Supported RSSI smoothing strategies.
enum RssiSmoothingMode {
  /// Exponential moving average.
  ema,

  /// Median of a fixed-size window.
  median,
}

/// Configuration for RSSI smoothing.
class RssiSmoothingSettings {
  final int windowSize;
  final RssiSmoothingMode mode;

  /// EMA alpha in (0, 1]. Higher reacts faster.
  final double emaAlpha;

  const RssiSmoothingSettings({
    this.windowSize = 5,
    this.mode = RssiSmoothingMode.ema,
    this.emaAlpha = 0.35,
  })  : assert(windowSize >= 1),
        assert(emaAlpha > 0 && emaAlpha <= 1);
}

/// Stateful tracker for a single device's RSSI observations.
///
/// This keeps a short history and produces a smoothed RSSI, plus a stable
/// visibility decision using hysteresis thresholds.
class RssiVisibilityTracker {
  final RssiSmoothingSettings smoothing;

  /// Last time we observed this device (even if not currently visible).
  DateTime lastSeen;

  /// Whether the device is currently considered visible.
  bool isVisible;

  final List<int> _samples = <int>[];
  double? _ema;

  RssiVisibilityTracker({
    required this.smoothing,
    required this.lastSeen,
    this.isVisible = false,
  });

  /// Raw RSSI samples (most recent last). Exposed for diagnostics/testing.
  List<int> get samples => List<int>.unmodifiable(_samples);

  /// Returns the current smoothed RSSI (rounded to int) if any samples exist.
  int? get smoothedRssi {
    if (_samples.isEmpty) return null;

    switch (smoothing.mode) {
      case RssiSmoothingMode.ema:
        return (_ema ?? _samples.last.toDouble()).round();
      case RssiSmoothingMode.median:
        return _median(_samples);
    }
  }

  /// Observe a new RSSI sample and update smoothed value + hysteresis state.
  ///
  /// Hysteresis rules:
  /// - If not visible: become visible when smoothed >= enterThresholdDbm
  /// - If visible: become invisible when smoothed < exitThresholdDbm
  void observe({
    required int rssi,
    required DateTime at,
    required int enterThresholdDbm,
    required int exitThresholdDbm,
  }) {
    lastSeen = at;

    _samples.add(rssi);
    if (_samples.length > smoothing.windowSize) {
      _samples.removeAt(0);
    }

    if (smoothing.mode == RssiSmoothingMode.ema) {
      final alpha = smoothing.emaAlpha;
      final x = rssi.toDouble();
      final prev = _ema ?? x;
      _ema = (alpha * x) + ((1 - alpha) * prev);
    }

    final s = smoothedRssi;
    if (s == null) return;

    if (!isVisible) {
      if (s >= enterThresholdDbm) {
        isVisible = true;
      }
      return;
    }

    if (s < exitThresholdDbm) {
      isVisible = false;
    }
  }

  static int _median(List<int> values) {
    if (values.isEmpty) {
      throw StateError('Cannot compute median of empty list');
    }
    final sorted = List<int>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    }
    // Even-sized median: average the two middle values.
    final a = sorted[mid - 1];
    final b = sorted[mid];
    return ((a + b) / 2).round();
  }

  /// Clamp RSSI to a plausible dBm range.
  static int clampDbm(int value) => value.clamp(-127, 20);

  /// Utility: derive an exit threshold from an enter threshold and hysteresis.
  static int deriveExitThreshold({
    required int enterThresholdDbm,
    required int hysteresisDb,
  }) {
    final delta = math.max(0, hysteresisDb).toInt();
    final exit = enterThresholdDbm - delta;
    return clampDbm(exit);
  }
}
