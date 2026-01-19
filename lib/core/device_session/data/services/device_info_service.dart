import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../domain/entities/device_session.dart';

/// Service for collecting comprehensive device, app, and network information.
///
/// This service gathers information for security monitoring and debugging purposes.
@lazySingleton
class DeviceInfoService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final Connectivity _connectivity = Connectivity();
  final Uuid _uuid = const Uuid();

  /// Collect all device and network information
  Future<DeviceSession> collectDeviceSession(
    String userId,
    String sessionType,
  ) async {
    final sessionId = _uuid.v4();
    final timestamp = DateTime.now();

    // Collect data in parallel where possible
    final results = await Future.wait<Map<String, dynamic>>([
      _getDeviceInfo(),
      _getAppInfo(),
      _getNetworkInfo(),
      _getLocationInfo(),
    ]);

    final deviceInfo = results[0];
    final appInfo = results[1];
    final networkInfo = results[2];
    final locationInfo = results[3];

    return DeviceSession(
      sessionId: sessionId,
      userId: userId,
      timestamp: timestamp,
      sessionType: sessionType,
      // Device info
      deviceBrand: deviceInfo['brand'] as String?,
      deviceModel: deviceInfo['model'] as String?,
      deviceType: deviceInfo['type'] as String?,
      screenResolution: deviceInfo['screenResolution'] as String?,
      screenDensity: deviceInfo['screenDensity'] as double?,
      operatingSystem: deviceInfo['os'] as String?,
      osVersion: deviceInfo['osVersion'] as String?,
      buildNumber: deviceInfo['buildNumber'] as String?,
      // App info
      appVersion: appInfo['version'] as String?,
      appBuildNumber: appInfo['buildNumber'] as String?,
      installSource: appInfo['installSource'] as String?,
      // Network info
      ipAddress: networkInfo['ipAddress'] as String?,
      networkType: networkInfo['networkType'] as String?,
      carrierName: networkInfo['carrierName'] as String?,
      // Location info
      country: locationInfo['country'] as String?,
      city: locationInfo['city'] as String?,
      isp: locationInfo['isp'] as String?,
    );
  }

  /// Get device information
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        return await _getAndroidDeviceInfo();
      } else if (Platform.isIOS) {
        return await _getIosDeviceInfo();
      }
    } catch (e) {
      // Silently fail and return partial data
      debugPrint('Error collecting device info: $e');
    }
    return {};
  }

  /// Get Android device information
  Future<Map<String, dynamic>> _getAndroidDeviceInfo() async {
    final androidInfo = await _deviceInfo.androidInfo;
    
    // Determine device type
    String deviceType = 'phone';
    if (androidInfo.isPhysicalDevice == false) {
      deviceType = 'emulator';
    } else {
      // Simple heuristic for tablets based on model name
      final model = androidInfo.model.toLowerCase();
      if (model.contains('tablet') || model.contains('pad')) {
        deviceType = 'tablet';
      }
    }

    return {
      'brand': androidInfo.brand,
      'model': androidInfo.model,
      'type': deviceType,
      'screenResolution': null, // Screen metrics not easily available
      'screenDensity': null,
      'os': 'Android',
      'osVersion': androidInfo.version.release,
      'buildNumber': androidInfo.version.sdkInt.toString(),
    };
  }

  /// Get iOS device information
  Future<Map<String, dynamic>> _getIosDeviceInfo() async {
    final iosInfo = await _deviceInfo.iosInfo;
    
    // Determine device type
    String deviceType = 'phone';
    if (iosInfo.isPhysicalDevice == false) {
      deviceType = 'emulator';
    } else if (iosInfo.model.toLowerCase().contains('ipad')) {
      deviceType = 'tablet';
    }

    return {
      'brand': 'Apple',
      'model': iosInfo.utsname.machine,
      'type': deviceType,
      'screenResolution': null, // iOS doesn't provide this easily
      'screenDensity': null,
      'os': 'iOS',
      'osVersion': iosInfo.systemVersion,
      'buildNumber': iosInfo.utsname.version,
    };
  }

  /// Get app information
  Future<Map<String, dynamic>> _getAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      
      // Determine install source
      String? installSource;
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        // On Android, we can sometimes determine the installer package
        // This would require platform-specific code via method channel
        // For now, we'll use a heuristic based on whether it's a physical device
        installSource = androidInfo.isPhysicalDevice ? 'unknown' : 'debug';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        installSource = iosInfo.isPhysicalDevice ? 'App Store' : 'debug';
      }

      return {
        'version': packageInfo.version,
        'buildNumber': packageInfo.buildNumber,
        'installSource': installSource,
      };
    } catch (e) {
      debugPrint('Error collecting app info: $e');
      return {};
    }
  }

  /// Get network information
  Future<Map<String, dynamic>> _getNetworkInfo() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      
      String networkType = 'unknown';
      if (connectivityResults.contains(ConnectivityResult.wifi)) {
        networkType = 'WiFi';
      } else if (connectivityResults.contains(ConnectivityResult.mobile)) {
        networkType = 'cellular';
      } else if (connectivityResults.contains(ConnectivityResult.ethernet)) {
        networkType = 'ethernet';
      }

      // Get carrier name for Android
      String? carrierName;
      if (Platform.isAndroid && networkType == 'cellular') {
        // This would require platform-specific code to get carrier name
        // For now, leave as null
        carrierName = null;
      }

      // Get public IP address
      String? ipAddress;
      try {
        // Use a free IP API service to get public IP
        final response = await http.get(
          Uri.parse('https://api.ipify.org?format=json'),
        ).timeout(const Duration(seconds: 5));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          ipAddress = data['ip'] as String?;
        }
      } catch (e) {
        debugPrint('Error getting IP address: $e');
      }

      return {
        'networkType': networkType,
        'carrierName': carrierName,
        'ipAddress': ipAddress,
      };
    } catch (e) {
      debugPrint('Error collecting network info: $e');
      return {};
    }
  }

  /// Get location and ISP information
  Future<Map<String, dynamic>> _getLocationInfo() async {
    try {
      // Get IP-based geolocation using a free service
      final response = await http.get(
        Uri.parse('http://ip-api.com/json/'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'country': data['country'] as String?,
          'city': data['city'] as String?,
          'isp': data['isp'] as String?,
        };
      }
    } catch (e) {
      debugPrint('Error getting location info: $e');
    }
    
    return {};
  }
}
