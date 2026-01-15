import 'dart:io';

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

    // Check Bluetooth adapter state
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      return BlePermissionStatus.bluetoothOff;
    }

    if (Platform.isAndroid) {
      return _checkAndroidPermissions();
    } else if (Platform.isIOS) {
      return _checkIOSPermissions();
    }

    return BlePermissionStatus.denied;
  }

  /// Checks Android-specific permissions.
  Future<BlePermissionStatus> _checkAndroidPermissions() async {
    // Android 12+ requires BLUETOOTH_SCAN and BLUETOOTH_ADVERTISE
    // Android 11 and below requires location permission

    final permissions = <Permission>[];

    // Bluetooth permissions (Android 12+)
    permissions.add(Permission.bluetoothScan);
    permissions.add(Permission.bluetoothAdvertise);
    permissions.add(Permission.bluetoothConnect);

    // Location permission (required for BLE scanning on Android)
    permissions.add(Permission.locationWhenInUse);

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
    final locationGranted =
        statuses[Permission.locationWhenInUse]?.isGranted ?? false;

    // Location must be enabled for BLE scanning on Android
    if (locationGranted) {
      final locationServiceEnabled = await Permission.location.serviceStatus;
      if (!locationServiceEnabled.isEnabled) {
        return BlePermissionStatus.locationOff;
      }
    }

    if (bluetoothScanGranted && bluetoothAdvertiseGranted && locationGranted) {
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

  /// Checks if Bluetooth is currently on.
  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Requests the user to turn on Bluetooth (Android only).
  Future<void> requestBluetoothOn() async {
    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }
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
