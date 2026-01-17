import 'package:equatable/equatable.dart';

/// Represents a discovered BLE device.
class BleDevice extends Equatable {
  /// The username of the discovered device (7 ASCII characters).
  final String username;

  /// The raw device ID (platform-specific, for internal use).
  final String deviceId;

  /// Signal strength (RSSI) in dBm.
  /// Higher values (closer to 0) indicate closer proximity.
  final int rssi;

  /// Timestamp when this device was last seen.
  final DateTime lastSeen;

  const BleDevice({
    required this.username,
    required this.deviceId,
    required this.rssi,
    required this.lastSeen,
  });

  /// Creates a copy with updated fields.
  BleDevice copyWith({
    String? username,
    String? deviceId,
    int? rssi,
    DateTime? lastSeen,
  }) {
    return BleDevice(
      username: username ?? this.username,
      deviceId: deviceId ?? this.deviceId,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [
        username,
        deviceId,
        rssi,
        lastSeen,
      ];

  @override
  String toString() {
    return 'BleDevice(username: $username, rssi: $rssi)';
  }
}
