import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/device_session.dart';

/// Data model for [DeviceSession] entity with Firestore serialization.
class DeviceSessionModel {
  final String sessionId;
  final String userId;
  final DateTime timestamp;
  final String? deviceBrand;
  final String? deviceModel;
  final String? deviceType;
  final String? screenResolution;
  final double? screenDensity;
  final String? operatingSystem;
  final String? osVersion;
  final String? buildNumber;
  final String? appVersion;
  final String? appBuildNumber;
  final String? installSource;
  final String? ipAddress;
  final String? networkType;
  final String? carrierName;
  final String sessionType;

  const DeviceSessionModel({
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
    this.networkType,
    this.carrierName,
  });

  /// Convert entity to model
  factory DeviceSessionModel.fromEntity(DeviceSession entity) {
    return DeviceSessionModel(
      sessionId: entity.sessionId,
      userId: entity.userId,
      timestamp: entity.timestamp,
      sessionType: entity.sessionType,
      deviceBrand: entity.deviceBrand,
      deviceModel: entity.deviceModel,
      deviceType: entity.deviceType,
      screenResolution: entity.screenResolution,
      screenDensity: entity.screenDensity,
      operatingSystem: entity.operatingSystem,
      osVersion: entity.osVersion,
      buildNumber: entity.buildNumber,
      appVersion: entity.appVersion,
      appBuildNumber: entity.appBuildNumber,
      installSource: entity.installSource,
      ipAddress: entity.ipAddress,
      networkType: entity.networkType,
      carrierName: entity.carrierName,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'sessionId': sessionId,
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
      'sessionType': sessionType,
      'deviceBrand': deviceBrand,
      'deviceModel': deviceModel,
      'deviceType': deviceType,
      'screenResolution': screenResolution,
      'screenDensity': screenDensity,
      'operatingSystem': operatingSystem,
      'osVersion': osVersion,
      'buildNumber': buildNumber,
      'appVersion': appVersion,
      'appBuildNumber': appBuildNumber,
      'installSource': installSource,
      'ipAddress': ipAddress,
      'networkType': networkType,
      'carrierName': carrierName,
    };
  }

  /// Convert from Firestore document
  factory DeviceSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DeviceSessionModel(
      sessionId: data['sessionId'] as String,
      userId: data['userId'] as String,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      sessionType: data['sessionType'] as String,
      deviceBrand: data['deviceBrand'] as String?,
      deviceModel: data['deviceModel'] as String?,
      deviceType: data['deviceType'] as String?,
      screenResolution: data['screenResolution'] as String?,
      screenDensity: (data['screenDensity'] as num?)?.toDouble(),
      operatingSystem: data['operatingSystem'] as String?,
      osVersion: data['osVersion'] as String?,
      buildNumber: data['buildNumber'] as String?,
      appVersion: data['appVersion'] as String?,
      appBuildNumber: data['appBuildNumber'] as String?,
      installSource: data['installSource'] as String?,
      ipAddress: data['ipAddress'] as String?,
      networkType: data['networkType'] as String?,
      carrierName: data['carrierName'] as String?,
    );
  }

  /// Convert model to entity
  DeviceSession toEntity() {
    return DeviceSession(
      sessionId: sessionId,
      userId: userId,
      timestamp: timestamp,
      sessionType: sessionType,
      deviceBrand: deviceBrand,
      deviceModel: deviceModel,
      deviceType: deviceType,
      screenResolution: screenResolution,
      screenDensity: screenDensity,
      operatingSystem: operatingSystem,
      osVersion: osVersion,
      buildNumber: buildNumber,
      appVersion: appVersion,
      appBuildNumber: appBuildNumber,
      installSource: installSource,
      ipAddress: ipAddress,
      networkType: networkType,
      carrierName: carrierName,
    );
  }
}
