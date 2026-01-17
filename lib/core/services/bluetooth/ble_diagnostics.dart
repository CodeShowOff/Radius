import 'dart:async';

/// Raw BLE device info for diagnostics
class RawBleDevice {
  final String deviceId;
  final String name;
  final int rssi;
  final List<String> serviceUuids;
  final Map<String, List<int>> serviceData;
  final DateTime lastSeen;

  RawBleDevice({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    required this.serviceData,
    required this.lastSeen,
  });
}

/// BLE diagnostics data for UI display
class BleDiagnostics {
  final bool isScanning;
  final bool isAdvertising;
  final DateTime? lastAdvertiseTime;
  final DateTime? lastScanTime;
  final int rawDeviceCount;
  final int parsedDeviceCount;
  final List<RawBleDevice> rawDevices;
  final String? lastError;

  BleDiagnostics({
    this.isScanning = false,
    this.isAdvertising = false,
    this.lastAdvertiseTime,
    this.lastScanTime,
    this.rawDeviceCount = 0,
    this.parsedDeviceCount = 0,
    this.rawDevices = const [],
    this.lastError,
  });

  BleDiagnostics copyWith({
    bool? isScanning,
    bool? isAdvertising,
    DateTime? lastAdvertiseTime,
    DateTime? lastScanTime,
    int? rawDeviceCount,
    int? parsedDeviceCount,
    List<RawBleDevice>? rawDevices,
    String? lastError,
  }) {
    return BleDiagnostics(
      isScanning: isScanning ?? this.isScanning,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      lastAdvertiseTime: lastAdvertiseTime ?? this.lastAdvertiseTime,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      rawDeviceCount: rawDeviceCount ?? this.rawDeviceCount,
      parsedDeviceCount: parsedDeviceCount ?? this.parsedDeviceCount,
      rawDevices: rawDevices ?? this.rawDevices,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Singleton service for BLE diagnostics
class BleDiagnosticsService {
  static final BleDiagnosticsService _instance =
      BleDiagnosticsService._internal();
  factory BleDiagnosticsService() => _instance;
  BleDiagnosticsService._internal();

  final _diagnosticsController = StreamController<BleDiagnostics>.broadcast();
  BleDiagnostics _currentDiagnostics = BleDiagnostics();

  Stream<BleDiagnostics> get diagnosticsStream => _diagnosticsController.stream;
  BleDiagnostics get currentDiagnostics => _currentDiagnostics;

  void updateScanning(bool isScanning) {
    _currentDiagnostics = _currentDiagnostics.copyWith(
      isScanning: isScanning,
      lastScanTime:
          isScanning ? DateTime.now() : _currentDiagnostics.lastScanTime,
    );
    _diagnosticsController.add(_currentDiagnostics);
  }

  void updateAdvertising(bool isAdvertising) {
    _currentDiagnostics = _currentDiagnostics.copyWith(
      isAdvertising: isAdvertising,
      lastAdvertiseTime: isAdvertising
          ? DateTime.now()
          : _currentDiagnostics.lastAdvertiseTime,
    );
    _diagnosticsController.add(_currentDiagnostics);
  }

  void updateRawDevices(List<RawBleDevice> devices, int parsedCount) {
    _currentDiagnostics = _currentDiagnostics.copyWith(
      rawDevices: devices,
      rawDeviceCount: devices.length,
      parsedDeviceCount: parsedCount,
    );
    _diagnosticsController.add(_currentDiagnostics);
  }

  void updateError(String? error) {
    _currentDiagnostics = _currentDiagnostics.copyWith(lastError: error);
    _diagnosticsController.add(_currentDiagnostics);
  }

  void dispose() {
    _diagnosticsController.close();
  }
}
