import 'package:equatable/equatable.dart';

/// Represents a discovered BLE device.
class BleDevice extends Equatable {
  /// The anonymous rotating ID broadcasted by the device.
  final String anonymousId;

  /// The raw device ID (platform-specific, for internal use).
  final String deviceId;

  /// Signal strength (RSSI) in dBm.
  /// Higher values (closer to 0) indicate closer proximity.
  final int rssi;

  /// Estimated distance category based on RSSI.
  final BleProximity proximity;

  /// Timestamp when this device was last seen.
  final DateTime lastSeen;

  /// Whether this device is broadcasting the Radius service.
  final bool isRadiusDevice;

  /// Optional device name (if available).
  final String? deviceName;

  const BleDevice({
    required this.anonymousId,
    required this.deviceId,
    required this.rssi,
    required this.proximity,
    required this.lastSeen,
    this.isRadiusDevice = true,
    this.deviceName,
  });

  /// Creates a copy with updated fields.
  BleDevice copyWith({
    String? anonymousId,
    String? deviceId,
    int? rssi,
    BleProximity? proximity,
    DateTime? lastSeen,
    bool? isRadiusDevice,
    String? deviceName,
  }) {
    return BleDevice(
      anonymousId: anonymousId ?? this.anonymousId,
      deviceId: deviceId ?? this.deviceId,
      rssi: rssi ?? this.rssi,
      proximity: proximity ?? this.proximity,
      lastSeen: lastSeen ?? this.lastSeen,
      isRadiusDevice: isRadiusDevice ?? this.isRadiusDevice,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  /// Calculates proximity category from RSSI value.
  static BleProximity calculateProximity(int rssi) {
    if (rssi >= -50) {
      return BleProximity.immediate; // < 1 meter
    } else if (rssi >= -70) {
      return BleProximity.near; // 1-5 meters
    } else if (rssi >= -90) {
      return BleProximity.far; // 5-10+ meters
    } else {
      return BleProximity.unknown;
    }
  }

  /// Rough distance estimation in meters based on RSSI.
  /// Note: This is an approximation and varies based on environment.
  double get estimatedDistanceMeters {
    // Using the log-distance path loss model
    // RSSI = -10 * n * log10(d) + A
    // where n = path loss exponent (~2 for free space, ~3-4 indoors)
    // A = RSSI at 1 meter (typically -59 to -65 dBm)
    const double txPower = -59; // Calibrated TX power at 1 meter
    const double n = 2.5; // Path loss exponent (indoor average)

    if (rssi == 0) return -1;

    final ratio = (txPower - rssi) / (10 * n);
    return double.parse(
      (10.0 * ratio).clamp(0.1, 100.0).toStringAsFixed(1),
    );
  }

  @override
  List<Object?> get props => [
        anonymousId,
        deviceId,
        rssi,
        proximity,
        lastSeen,
        isRadiusDevice,
        deviceName,
      ];

  @override
  String toString() {
    return 'BleDevice(anonymousId: $anonymousId, rssi: $rssi, proximity: $proximity)';
  }
}

/// Proximity categories based on RSSI values.
enum BleProximity {
  /// Device is very close (< 1 meter).
  immediate,

  /// Device is nearby (1-5 meters).
  near,

  /// Device is far but detectable (5-10+ meters).
  far,

  /// Unable to determine proximity.
  unknown,
}

/// Extension for proximity display strings.
extension BleProximityX on BleProximity {
  String get displayName {
    switch (this) {
      case BleProximity.immediate:
        return 'Very Close';
      case BleProximity.near:
        return 'Nearby';
      case BleProximity.far:
        return 'In Range';
      case BleProximity.unknown:
        return 'Unknown';
    }
  }

  String get description {
    switch (this) {
      case BleProximity.immediate:
        return 'Less than 1 meter away';
      case BleProximity.near:
        return 'Within 5 meters';
      case BleProximity.far:
        return 'Within 10 meters';
      case BleProximity.unknown:
        return 'Distance unknown';
    }
  }
}
