/// Bluetooth scan configuration for different power modes.
/// 
/// Adjusts scan duration, interval, and filtering based on
/// power requirements and app state.
class BleScanConfig {
  /// Duration of each scan cycle.
  final Duration scanDuration;

  /// Interval between scan cycles.
  final Duration scanInterval;

  /// Minimum RSSI to report device (-100 to 0).
  final int minRssi;

  /// Whether to report duplicate advertisements.
  final bool allowDuplicates;

  /// Service UUIDs to filter for (empty = all).
  final List<String> serviceUuids;

  const BleScanConfig({
    required this.scanDuration,
    required this.scanInterval,
    this.minRssi = -90,
    this.allowDuplicates = false,
    this.serviceUuids = const [],
  });

  /// High performance mode for foreground active use.
  /// 
  /// - Fast detection (~2 seconds)
  /// - Higher battery usage
  /// - Best for when user is actively looking at nearby users
  static const BleScanConfig active = BleScanConfig(
    scanDuration: Duration(seconds: 4),
    scanInterval: Duration(seconds: 6),
    minRssi: -85,
    allowDuplicates: true,
  );

  /// Balanced mode for normal use.
  /// 
  /// - Moderate detection speed (~10 seconds)
  /// - Balanced battery usage
  /// - Default for app in foreground
  static const BleScanConfig balanced = BleScanConfig(
    scanDuration: Duration(seconds: 3),
    scanInterval: Duration(seconds: 15),
    minRssi: -90,
    allowDuplicates: false,
  );

  /// Low power mode for background.
  /// 
  /// - Slower detection (~30 seconds)
  /// - Minimal battery usage
  /// - For background scanning
  static const BleScanConfig lowPower = BleScanConfig(
    scanDuration: Duration(seconds: 2),
    scanInterval: Duration(seconds: 30),
    minRssi: -95,
    allowDuplicates: false,
  );

  /// Battery saver mode.
  /// 
  /// - Very slow detection (~2 minutes)
  /// - Minimal battery usage
  /// - For low battery situations
  static const BleScanConfig batterySaver = BleScanConfig(
    scanDuration: Duration(seconds: 2),
    scanInterval: Duration(minutes: 2),
    minRssi: -95,
    allowDuplicates: false,
  );

  /// Select config based on app state and battery level.
  static BleScanConfig forContext({
    required bool isAppInForeground,
    required bool isUserActive,
    required int batteryLevel,
    required bool isPowerSaveMode,
  }) {
    // Battery saver if low battery or system power save
    if (batteryLevel < 15 || isPowerSaveMode) {
      return BleScanConfig.batterySaver;
    }

    // Background mode
    if (!isAppInForeground) {
      return BleScanConfig.lowPower;
    }

    // User actively using nearby feature
    if (isUserActive) {
      return BleScanConfig.active;
    }

    // Default foreground mode
    return BleScanConfig.balanced;
  }

  @override
  String toString() => 'BleScanConfig('
      'scan: ${scanDuration.inSeconds}s, '
      'interval: ${scanInterval.inSeconds}s, '
      'minRssi: $minRssi)';
}

/// Bluetooth advertisement configuration.
class BleAdvertiseConfig {
  /// Advertisement interval.
  final Duration advertiseInterval;

  /// Transmit power level (low/medium/high).
  final AdvertiseTxPower txPower;

  /// Whether to include device name.
  final bool includeName;

  /// Advertisement timeout (0 = forever).
  final Duration timeout;

  const BleAdvertiseConfig({
    required this.advertiseInterval,
    this.txPower = AdvertiseTxPower.medium,
    this.includeName = false,
    this.timeout = Duration.zero,
  });

  /// High visibility mode.
  static const BleAdvertiseConfig active = BleAdvertiseConfig(
    advertiseInterval: Duration(milliseconds: 100),
    txPower: AdvertiseTxPower.high,
  );

  /// Balanced mode.
  static const BleAdvertiseConfig balanced = BleAdvertiseConfig(
    advertiseInterval: Duration(milliseconds: 250),
    txPower: AdvertiseTxPower.medium,
  );

  /// Low power mode.
  static const BleAdvertiseConfig lowPower = BleAdvertiseConfig(
    advertiseInterval: Duration(milliseconds: 1000),
    txPower: AdvertiseTxPower.low,
  );
}

enum AdvertiseTxPower { low, medium, high }
