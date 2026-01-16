import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of permission check.
enum BlePermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  restricted,
  bluetoothOff,
  locationOff,
}

/// Handles BLE-related permissions for Android and iOS.
class BlePermissionHandler {
  /// Checks and requests all required BLE permissions.
  /// Returns [BlePermissionStatus] indicating the result.
  Future<BlePermissionStatus> checkAndRequestPermissions() async {
    // First check if Bluetooth is supported
    if (!await FlutterBluePlus.isSupported) {
      return BlePermissionStatus.restricted;
    }

    // Check Bluetooth adapter state FIRST (before requesting permissions)
    // This ensures we detect if Bluetooth is off immediately
    final bluetoothEnabled = await isBluetoothOn();
    if (!bluetoothEnabled) {
      return BlePermissionStatus.bluetoothOff;
    }

    // Request permissions
    BlePermissionStatus permissionStatus;
    if (Platform.isAndroid) {
      permissionStatus = await _checkAndroidPermissions();
    } else if (Platform.isIOS) {
      permissionStatus = await _checkIOSPermissions();
    } else {
      return BlePermissionStatus.denied;
    }

    // If permissions weren't granted, return that status
    if (permissionStatus != BlePermissionStatus.granted) {
      return permissionStatus;
    }

    // Double-check Bluetooth is still on after permission requests
    final stillOn = await isBluetoothOn();
    if (!stillOn) {
      return BlePermissionStatus.bluetoothOff;
    }

    return BlePermissionStatus.granted;
  }

  /// Gets the Android SDK version.
  Future<int> _getAndroidSdkVersion() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      return 30; // Default to Android 11 if we can't determine
    }
  }

  /// Checks Android-specific permissions.
  Future<BlePermissionStatus> _checkAndroidPermissions() async {
    // Get Android SDK version to determine permission requirements
    final sdkVersion = await _getAndroidSdkVersion();
    final isAndroid12OrHigher = sdkVersion >= 31;

    // Android 12+ (API 31+): Only need Bluetooth permissions (with neverForLocation flag in manifest)
    // Android 11 and below: Also need location permission for BLE scanning
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ];

    // Only request location on Android 11 and below
    if (!isAndroid12OrHigher) {
      permissions.add(Permission.locationWhenInUse);
    }

    // Request all permissions
    final statuses = await permissions.request();

    // Check if any permission is permanently denied
    for (final status in statuses.values) {
      if (status.isPermanentlyDenied) {
        return BlePermissionStatus.permanentlyDenied;
      }
    }

    // Check if all required permissions are granted
    final bluetoothScanGranted =
        statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final bluetoothAdvertiseGranted =
        statuses[Permission.bluetoothAdvertise]?.isGranted ?? false;
    final bluetoothConnectGranted =
        statuses[Permission.bluetoothConnect]?.isGranted ?? false;

    // For Android 11 and below, also check location
    if (!isAndroid12OrHigher) {
      final locationGranted =
          statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      if (!locationGranted) {
        return BlePermissionStatus.denied;
      }

      // Location service must be enabled for BLE scanning on Android 11 and below
      final locationServiceEnabled = await Permission.location.serviceStatus;
      if (!locationServiceEnabled.isEnabled) {
        return BlePermissionStatus.locationOff;
      }
    }

    if (bluetoothScanGranted &&
        bluetoothAdvertiseGranted &&
        bluetoothConnectGranted) {
      // IMPORTANT: Android requires Location Services to be ENABLED for BLE scanning
      // to work, even on Android 12+ with neverForLocation flag.
      // This is a platform limitation, not a permission issue.
      final locationServiceEnabled = await Permission.location.serviceStatus;
      if (!locationServiceEnabled.isEnabled) {
        return BlePermissionStatus.locationOff;
      }
      return BlePermissionStatus.granted;
    }

    return BlePermissionStatus.denied;
  }

  /// Checks iOS-specific permissions.
  Future<BlePermissionStatus> _checkIOSPermissions() async {
    // iOS uses Bluetooth permission
    final status = await Permission.bluetooth.request();

    if (status.isPermanentlyDenied) {
      return BlePermissionStatus.permanentlyDenied;
    }

    if (status.isGranted) {
      return BlePermissionStatus.granted;
    }

    if (status.isRestricted) {
      return BlePermissionStatus.restricted;
    }

    return BlePermissionStatus.denied;
  }

  /// Opens app settings for the user to manually grant permissions.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Opens location settings for the user to enable Location Services.
  Future<bool> openLocationSettings() async {
    if (Platform.isAndroid) {
      // Use Geolocator or direct intent - for now use app settings
      // The user can navigate to Location from there
      return await openAppSettings();
    }
    return false;
  }

  /// Checks if Location Services are enabled.
  Future<bool> isLocationServiceEnabled() async {
    final status = await Permission.location.serviceStatus;
    return status.isEnabled;
  }

  /// Checks if Bluetooth is currently on.
  /// Uses multiple methods for reliability.
  Future<bool> isBluetoothOn() async {
    try {
      // Method 1: Try to get the current adapter state directly
      // On Android, this is the most reliable method
      if (Platform.isAndroid) {
        try {
          // FlutterBluePlus.adapterState is a broadcast stream that emits the current state
          final state = await FlutterBluePlus.adapterState.first
              .timeout(const Duration(seconds: 1), onTimeout: () {
            return BluetoothAdapterState.unknown;
          });

          // If we got a definitive answer, use it
          if (state == BluetoothAdapterState.on) {
            return true;
          } else if (state == BluetoothAdapterState.off ||
              state == BluetoothAdapterState.turningOff) {
            return false;
          }
          // For unknown/turningOn, wait a bit longer
        } catch (_) {
          // Continue to fallback method
        }
      }

      // Method 2: Wait for a non-unknown state with timeout
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () {
        return BluetoothAdapterState.off;
      });
      return state == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  /// Requests the user to turn on Bluetooth (Android only).
  /// Returns true if successfully requested (user may still decline).
  Future<bool> requestBluetoothOn() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
        return true;
      } catch (e) {
        // User declined or error occurred
        return false;
      }
    }
    // On iOS, Bluetooth must be enabled via system settings
    return false;
  }

  /// Stream of Bluetooth adapter state changes.
  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  /// Gets human-readable message for permission status.
  String getPermissionMessage(BlePermissionStatus status) {
    switch (status) {
      case BlePermissionStatus.granted:
        return 'All permissions granted';
      case BlePermissionStatus.denied:
        return 'Bluetooth permissions are required to discover nearby users';
      case BlePermissionStatus.permanentlyDenied:
        return 'Bluetooth permissions were denied. Please enable them in Settings';
      case BlePermissionStatus.restricted:
        return 'Bluetooth is not available on this device';
      case BlePermissionStatus.bluetoothOff:
        return 'Please turn on Bluetooth to discover nearby users';
      case BlePermissionStatus.locationOff:
        return 'Please enable Location Services for Bluetooth scanning';
    }
  }
}
