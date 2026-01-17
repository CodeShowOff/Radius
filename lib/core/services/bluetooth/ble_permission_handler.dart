import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logging/device_log.dart';

/// Result of permission check.
enum BlePermissionStatus {
  granted,

  /// Scan is allowed, but advertising is not.
  ///
  /// Returned when the caller requests both scanning and advertising, scanning is
  /// granted, but advertising is denied.
  grantedScanOnly,
  denied,
  permanentlyDenied,

  /// One or more required permissions were permanently denied.
  /// UI should guide the user to Settings.
  permissionDeniedShowSettings,
  restricted,
  bluetoothOff,
  locationOff,
}

/// Handles BLE-related permissions for Android and iOS.
class BlePermissionHandler {
  final Future<int?> Function() _androidSdkIntProvider;
  final Future<Map<Permission, PermissionStatus>> Function(List<Permission>)
      _requestPermissions;
  final Future<bool> Function() _isLocationServiceEnabled;

  BlePermissionHandler({
    Future<int?> Function()? androidSdkIntProvider,
    Future<Map<Permission, PermissionStatus>> Function(List<Permission>)?
        requestPermissions,
    Future<bool> Function()? isLocationServiceEnabled,
  })  : _androidSdkIntProvider = androidSdkIntProvider ?? _defaultSdkProvider,
        _requestPermissions = requestPermissions ?? _defaultRequestPermissions,
        _isLocationServiceEnabled =
            isLocationServiceEnabled ?? _defaultLocationServiceEnabled;

  static Future<int?> _defaultSdkProvider() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<Permission, PermissionStatus>> _defaultRequestPermissions(
    List<Permission> permissions,
  ) async {
    return permissions.request();
  }

  static Future<bool> _defaultLocationServiceEnabled() async {
    return Permission.location.serviceStatus.isEnabled;
  }

  /// Checks and requests all required BLE permissions.
  /// Returns [BlePermissionStatus] indicating the result.
  Future<BlePermissionStatus> checkAndRequestPermissions({
    bool needsScan = true,
    bool needsConnect = true,
    bool needsAdvertise = false,
  }) async {
    DeviceLog.instance.debug('ble.perm', 'checkAndRequestPermissions()', data: {
      'needsScan': needsScan,
      'needsConnect': needsConnect,
      'needsAdvertise': needsAdvertise,
      'platform': defaultTargetPlatform.name,
    });

    // First check if Bluetooth is supported
    if (!await FlutterBluePlus.isSupported) {
      DeviceLog.instance.warning('ble.perm', 'Bluetooth not supported');
      return BlePermissionStatus.restricted;
    }

    // Request permissions (Android 12+ Bluetooth runtime permissions must be
    // granted before some adapter operations; so request first, then check
    // adapter state).
    BlePermissionStatus permissionStatus;
    if (Platform.isAndroid) {
      permissionStatus = await _checkAndroidPermissions(
        needsScan: needsScan,
        needsConnect: needsConnect,
        needsAdvertise: needsAdvertise,
      );
    } else if (Platform.isIOS) {
      permissionStatus = await _checkIOSPermissions();
    } else {
      return BlePermissionStatus.denied;
    }

    DeviceLog.instance.debug('ble.perm', 'permission check result', data: {
      'result': permissionStatus.name,
    });

    // If permissions weren't granted, return that status
    if (permissionStatus != BlePermissionStatus.granted) {
      return permissionStatus;
    }

    // Check Bluetooth adapter state after permissions are granted.
    final bluetoothEnabled = await isBluetoothOn();
    if (!bluetoothEnabled) {
      DeviceLog.instance.warning('ble.perm', 'Bluetooth off after permissions');
      return BlePermissionStatus.bluetoothOff;
    }

    return BlePermissionStatus.granted;
  }

  /// Checks Android-specific permissions.
  Future<BlePermissionStatus> _checkAndroidPermissions({
    required bool needsScan,
    required bool needsConnect,
    required bool needsAdvertise,
  }) async {
    // Android BLE runtime permissions:
    // - API 31+ uses BLUETOOTH_SCAN / BLUETOOTH_ADVERTISE / BLUETOOTH_CONNECT.
    // - API <= 30 may require ACCESS_FINE_LOCATION for scanning (plus Location services).
    // Docs: https://developer.android.com/guide/topics/connectivity/bluetooth/permissions
    final sdkInt = await _androidSdkIntProvider();

    DeviceLog.instance.debug('ble.perm', 'Android permission request', data: {
      'sdkInt': sdkInt,
      'needsScan': needsScan,
      'needsConnect': needsConnect,
      'needsAdvertise': needsAdvertise,
    });

    final isApi31Plus = sdkInt != null && sdkInt >= 31;

    // Build required permissions based on API level.
    // Note: BLUETOOTH_* are runtime permissions on Android 12+.
    final permissions = <Permission>[
      if (needsScan && isApi31Plus) Permission.bluetoothScan,
      if (needsAdvertise && isApi31Plus) Permission.bluetoothAdvertise,
      if (needsConnect && isApi31Plus) Permission.bluetoothConnect,
      if (needsScan && !isApi31Plus) Permission.location,
    ];

    // Request all permissions
    final statuses = await _requestPermissions(permissions);

    DeviceLog.instance.debug('ble.perm', 'Android permission statuses', data: {
      for (final e in statuses.entries) e.key.toString(): e.value.toString(),
    });

    // Determine permanent denial separately for each requested permission.
    // If anything required is permanently denied, UI should guide to Settings.
    bool permanentlyDenied = false;
    for (final entry in statuses.entries) {
      if (entry.value.isPermanentlyDenied) {
        permanentlyDenied = true;
      }
    }

    // Only require Location services for pre-Android 12 devices *when scanning*.
    if (needsScan && !isApi31Plus) {
      // Location service must be enabled (Android < 12). If it's off, scanning often
      // yields zero devices without throwing.
      final locationServiceEnabled = await _isLocationServiceEnabled();
      if (!locationServiceEnabled) {
        return BlePermissionStatus.locationOff;
      }
    }

    // Check required permissions independently.
    final scanGranted = !needsScan || (!isApi31Plus)
        ? (statuses[Permission.location]?.isGranted ?? true)
        : (statuses[Permission.bluetoothScan]?.isGranted ?? false);

    final advertiseGranted = !needsAdvertise || !isApi31Plus
        ? true
        : (statuses[Permission.bluetoothAdvertise]?.isGranted ?? false);

    final connectGranted = !needsConnect || !isApi31Plus
        ? true
        : (statuses[Permission.bluetoothConnect]?.isGranted ?? false);

    // If any required permission is permanently denied, provide a UI-guiding code.
    // Keep the legacy permanentlyDenied value for backwards compatibility.
    if (permanentlyDenied &&
        (!scanGranted || !advertiseGranted || !connectGranted)) {
      return BlePermissionStatus.permissionDeniedShowSettings;
    }

    // Full mode: all requested capabilities granted.
    if (scanGranted && advertiseGranted && connectGranted) {
      return BlePermissionStatus.granted;
    }

    // Scan-only mode: scanning is allowed, but advertising is not.
    if (needsScan && needsAdvertise && scanGranted && !advertiseGranted) {
      return BlePermissionStatus.grantedScanOnly;
    }

    // Fallback: denied.
    return permanentlyDenied
        ? BlePermissionStatus.permanentlyDenied
        : BlePermissionStatus.denied;
  }

  @visibleForTesting
  Future<BlePermissionStatus> checkAndroidPermissionsForTest({
    required bool needsScan,
    required bool needsConnect,
    required bool needsAdvertise,
  }) {
    return _checkAndroidPermissions(
      needsScan: needsScan,
      needsConnect: needsConnect,
      needsAdvertise: needsAdvertise,
    );
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
        // On Android 12+, turning on Bluetooth via system intent requires
        // BLUETOOTH_CONNECT.
        final connectStatus = await Permission.bluetoothConnect.request();
        if (!connectStatus.isGranted) {
          return false;
        }
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
      case BlePermissionStatus.grantedScanOnly:
        return 'Bluetooth scan is allowed, but advertising is not';
      case BlePermissionStatus.denied:
        return 'Bluetooth permissions are required to discover nearby users';
      case BlePermissionStatus.permanentlyDenied:
        return 'Bluetooth permissions were denied. Please enable them in Settings';
      case BlePermissionStatus.permissionDeniedShowSettings:
        return 'Bluetooth permissions were permanently denied. Please enable them in Settings';
      case BlePermissionStatus.restricted:
        return 'Bluetooth is not available on this device';
      case BlePermissionStatus.bluetoothOff:
        return 'Please turn on Bluetooth to discover nearby users';
      case BlePermissionStatus.locationOff:
        return 'Please turn on Location services to discover nearby users';
    }
  }

  /// Short, user-facing rationale that can be shown before requesting permissions.
  String getPermissionRationale() {
    return 'Radius uses Bluetooth to discover nearby users. On Android 12+ the system uses Bluetooth runtime permissions (BLUETOOTH_SCAN/CONNECT/ADVERTISE). On some older Android versions (especially Android 11 and below), the system may require Location permission and Location services enabled for BLE scanning (no GPS data is collected).';
  }
}
