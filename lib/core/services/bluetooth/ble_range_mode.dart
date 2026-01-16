/// User-selectable BLE discovery range preset.
///
/// Note: BLE does not provide an exact "range" setting. These presets adjust
/// radio parameters we control (scan mode / advertising power where possible)
/// and app-level filtering (RSSI threshold) to bias towards shorter or longer
/// effective discovery distances.
enum BleRangeMode {
  /// Prefer nearby-only results (strong RSSI), lower transmit power.
  short,

  /// Prefer maximum discoverability (weaker RSSI allowed), higher transmit power.
  large,
}

extension BleRangeModeX on BleRangeMode {
  String get label {
    switch (this) {
      case BleRangeMode.short:
        return 'Short range';
      case BleRangeMode.large:
        return 'Large range';
    }
  }

  String get description {
    switch (this) {
      case BleRangeMode.short:
        return 'Shows mostly very nearby devices. Lower battery/radio impact.';
      case BleRangeMode.large:
        return 'Tries to discover devices farther away. Higher battery/radio impact.';
    }
  }

  /// Minimum RSSI accepted by the scanner.
  ///
  /// RSSI is environmental; these values are heuristics.
  int get minRssiThreshold {
    switch (this) {
      case BleRangeMode.short:
        return -75;
      case BleRangeMode.large:
        // Debug-friendly: accept any RSSI so we can validate discovery first.
        return -127;
    }
  }

  /// Android advertiser tx power mapping.
  /// 0=LOW, 1=MEDIUM, 2=HIGH
  int get androidTxPowerLevel {
    switch (this) {
      case BleRangeMode.short:
        return 0;
      case BleRangeMode.large:
        return 2;
    }
  }

  /// Android advertise mode mapping.
  /// 0=LOW_POWER, 1=BALANCED, 2=LOW_LATENCY
  int get androidAdvertiseMode {
    switch (this) {
      case BleRangeMode.short:
        return 1;
      case BleRangeMode.large:
        return 2;
    }
  }
}
