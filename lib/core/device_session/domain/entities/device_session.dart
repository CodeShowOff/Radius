import 'package:equatable/equatable.dart';

/// Entity representing a device session for security and debugging purposes.
///
/// This entity stores comprehensive device, network, and app information
/// collected during user login/registration for security monitoring and debugging.
class DeviceSession extends Equatable {
  /// Unique identifier for the session
  final String sessionId;

  /// User ID this session belongs to
  final String userId;

  /// Timestamp when the session was created
  final DateTime timestamp;

  /// Device brand (e.g., "Samsung", "Apple")
  final String? deviceBrand;

  /// Device model (e.g., "Galaxy S21", "iPhone 14 Pro")
  final String? deviceModel;

  /// Device type (e.g., "phone", "tablet", "emulator")
  final String? deviceType;

  /// Screen resolution (e.g., "1080x2400")
  final String? screenResolution;

  /// Screen density/DPI
  final double? screenDensity;

  /// Operating system (e.g., "Android", "iOS")
  final String? operatingSystem;

  /// OS version (e.g., "14.0", "33")
  final String? osVersion;

  /// Device build number
  final String? buildNumber;

  /// App version (e.g., "1.0.0")
  final String? appVersion;

  /// App build number (e.g., "1")
  final String? appBuildNumber;

  /// Install source (e.g., "Play Store", "App Store", "sideload")
  final String? installSource;

  /// IP address (IPv4/IPv6)
  final String? ipAddress;

  /// Approximate country
  final String? country;

  /// Approximate city
  final String? city;

  /// Internet Service Provider / ASN
  final String? isp;

  /// Network type (e.g., "WiFi", "cellular", "ethernet")
  final String? networkType;

  /// Mobile carrier name (if applicable)
  final String? carrierName;

  /// Session type (e.g., "login", "register")
  final String sessionType;

  const DeviceSession({
    required this.sessionId,
    required this.userId,
    required this.timestamp,
    required this.sessionType,
    this.deviceBrand,
    this.deviceModel,
    this.deviceType,
    this.screenResolution,
    this.screenDensity,
    this.operatingSystem,
    this.osVersion,
    this.buildNumber,
    this.appVersion,
    this.appBuildNumber,
    this.installSource,
    this.ipAddress,
    this.country,
    this.city,
    this.isp,
    this.networkType,
    this.carrierName,
  });

  @override
  List<Object?> get props => [
        sessionId,
        userId,
        timestamp,
        deviceBrand,
        deviceModel,
        deviceType,
        screenResolution,
        screenDensity,
        operatingSystem,
        osVersion,
        buildNumber,
        appVersion,
        appBuildNumber,
        installSource,
        ipAddress,
        country,
        city,
        isp,
        networkType,
        carrierName,
        sessionType,
      ];
}
