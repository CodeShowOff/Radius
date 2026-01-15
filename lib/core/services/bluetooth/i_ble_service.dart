/// Bluetooth adapter state.
enum BluetoothState {
  unknown,
  unavailable,
  unauthorized,
  turningOn,
  on,
  turningOff,
  off,
}

/// Bluetooth Low Energy service interface.
///
/// Abstracts platform-specific BLE implementations.
/// Implementation will use flutter_blue_plus or similar library.
abstract class IBleService {
  /// Stream of Bluetooth adapter state.
  Stream<BluetoothState> get stateStream;

  /// Current Bluetooth state.
  Future<BluetoothState> get currentState;

  /// Stream of discovered BLE devices.
  Stream<BleDevice> get scanResultsStream;

  /// Whether currently scanning.
  bool get isScanning;

  /// Whether currently advertising.
  bool get isAdvertising;

  /// Start BLE scanning.
  Future<void> startScan({
    Duration? timeout,
    ScanMode scanMode = ScanMode.lowLatency,
    List<String>? serviceUuids,
  });

  /// Stop BLE scanning.
  Future<void> stopScan();

  /// Start BLE advertising.
  Future<void> startAdvertising({
    required String serviceUuid,
    required List<int> serviceData,
    AdvertiseMode mode = AdvertiseMode.balanced,
  });

  /// Stop BLE advertising.
  Future<void> stopAdvertising();

  /// Request necessary permissions.
  Future<bool> requestPermissions();

  /// Check if BLE is supported on this device.
  Future<bool> isSupported();

  /// Enable Bluetooth adapter (Android only).
  Future<void> turnOn();
}

/// Discovered BLE device information.
class BleDevice {
  final String id;
  final String? name;
  final int rssi;
  final List<int>? serviceData;
  final List<String> serviceUuids;
  final DateTime timestamp;

  const BleDevice({
    required this.id,
    this.name,
    required this.rssi,
    this.serviceData,
    required this.serviceUuids,
    required this.timestamp,
  });

  /// Estimate distance from RSSI value.
  /// Uses path loss model: RSSI = -10n * log10(d) + A
  /// Where n ≈ 2 (free space), A ≈ -59 (RSSI at 1 meter)
  double get estimatedDistance {
    const int txPower = -59; // Calibrated RSSI at 1 meter
    // Path loss exponent ~2.0 for free space

    if (rssi == 0) return -1;

    final ratio = rssi / txPower;
    if (ratio < 1.0) {
      return ratio * ratio * ratio;
    }

    return (0.89976 * (ratio * ratio * ratio)) + 0.111;
  }
}

/// BLE scan modes (maps to Android scan modes).
enum ScanMode {
  /// Battery efficient, slower discovery.
  lowPower,

  /// Balance between battery and latency.
  balanced,

  /// Fastest discovery, highest battery usage.
  lowLatency,

  /// Use when other apps are scanning.
  opportunistic,
}

/// BLE advertise modes.
enum AdvertiseMode {
  /// Low power advertising (1000ms interval).
  lowPower,

  /// Balanced advertising (250ms interval).
  balanced,

  /// Low latency advertising (100ms interval).
  lowLatency,
}
