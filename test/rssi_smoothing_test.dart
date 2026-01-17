import 'package:flutter_test/flutter_test.dart';
import 'package:radius/core/services/bluetooth/rssi_smoothing.dart';

void main() {
  group('RssiVisibilityTracker', () {
    test('stays visible across short RSSI drops (median + hysteresis)', () {
      final start = DateTime(2026, 1, 1, 0, 0, 0);
      final tracker = RssiVisibilityTracker(
        smoothing: const RssiSmoothingSettings(
          windowSize: 5,
          mode: RssiSmoothingMode.median,
        ),
        lastSeen: start,
      );

      // Enter visibility with a strong signal.
      tracker.observe(
        rssi: -74,
        at: start,
        enterThresholdDbm: -75,
        exitThresholdDbm: -85,
      );
      expect(tracker.isVisible, isTrue);

      // Fluctuate with occasional brief dips but not sustained below exit.
      final readings = <int>[-80, -83, -82, -86, -81, -84, -83];
      var t = start;
      for (final rssi in readings) {
        t = t.add(const Duration(seconds: 1));
        tracker.observe(
          rssi: rssi,
          at: t,
          enterThresholdDbm: -75,
          exitThresholdDbm: -85,
        );
      }

      // Should remain visible due to hysteresis and median smoothing.
      expect(tracker.isVisible, isTrue);
    });

    test(
        'sustained drop below exit threshold hides eventually (EMA + hysteresis)',
        () {
      final start = DateTime(2026, 1, 1, 0, 0, 0);
      final tracker = RssiVisibilityTracker(
        smoothing: const RssiSmoothingSettings(
          windowSize: 5,
          mode: RssiSmoothingMode.ema,
          emaAlpha: 0.35,
        ),
        lastSeen: start,
      );

      // Enter visibility.
      tracker.observe(
        rssi: -70,
        at: start,
        enterThresholdDbm: -75,
        exitThresholdDbm: -85,
      );
      expect(tracker.isVisible, isTrue);

      // Now sustained low RSSI should pull EMA below exit threshold.
      var t = start;
      for (var i = 0; i < 20; i++) {
        t = t.add(const Duration(seconds: 1));
        tracker.observe(
          rssi: -95,
          at: t,
          enterThresholdDbm: -75,
          exitThresholdDbm: -85,
        );
      }

      expect(tracker.isVisible, isFalse);
      expect(tracker.smoothedRssi, isNotNull);
      expect(tracker.smoothedRssi!, lessThan(-85));
    });
  });
}
