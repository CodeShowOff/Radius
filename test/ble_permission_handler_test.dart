import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:radius/core/services/bluetooth/ble_permission_handler.dart';

void main() {
  group('BlePermissionHandler Android permission mapping', () {
    test('API >= 31 requests BLUETOOTH_SCAN/ADVERTISE/CONNECT as needed',
        () async {
      final requested = <Permission>[];

      final handler = BlePermissionHandler(
        androidSdkIntProvider: () async => 33,
        requestPermissions: (perms) async {
          requested
            ..clear()
            ..addAll(perms);
          return {
            for (final p in perms) p: PermissionStatus.granted,
          };
        },
        isLocationServiceEnabled: () async => true,
      );

      final status = await handler.checkAndroidPermissionsForTest(
        needsScan: true,
        needsConnect: true,
        needsAdvertise: true,
      );

      expect(status, BlePermissionStatus.granted);
      expect(
          requested,
          containsAll(<Permission>[
            Permission.bluetoothScan,
            Permission.bluetoothAdvertise,
            Permission.bluetoothConnect,
          ]));
      expect(requested, isNot(contains(Permission.location)));
    });

    test('API < 31 uses location fallback for scanning', () async {
      final requested = <Permission>[];

      final handler = BlePermissionHandler(
        androidSdkIntProvider: () async => 30,
        requestPermissions: (perms) async {
          requested
            ..clear()
            ..addAll(perms);
          return {
            for (final p in perms) p: PermissionStatus.granted,
          };
        },
        isLocationServiceEnabled: () async => true,
      );

      final status = await handler.checkAndroidPermissionsForTest(
        needsScan: true,
        needsConnect: false,
        needsAdvertise: false,
      );

      expect(status, BlePermissionStatus.granted);
      expect(requested, contains(Permission.location));
      expect(requested, isNot(contains(Permission.bluetoothScan)));
      expect(requested, isNot(contains(Permission.bluetoothAdvertise)));
      expect(requested, isNot(contains(Permission.bluetoothConnect)));
    });

    test('API < 31 returns locationOff when location services disabled',
        () async {
      final handler = BlePermissionHandler(
        androidSdkIntProvider: () async => 29,
        requestPermissions: (perms) async => {
          for (final p in perms) p: PermissionStatus.granted,
        },
        isLocationServiceEnabled: () async => false,
      );

      final status = await handler.checkAndroidPermissionsForTest(
        needsScan: true,
        needsConnect: false,
        needsAdvertise: false,
      );

      expect(status, BlePermissionStatus.locationOff);
    });

    test('API >= 31 scan-only mode returns grantedScanOnly', () async {
      final handler = BlePermissionHandler(
        androidSdkIntProvider: () async => 34,
        requestPermissions: (perms) async {
          return {
            for (final p in perms)
              p: (p == Permission.bluetoothAdvertise)
                  ? PermissionStatus.denied
                  : PermissionStatus.granted,
          };
        },
        isLocationServiceEnabled: () async => true,
      );

      final status = await handler.checkAndroidPermissionsForTest(
        needsScan: true,
        needsConnect: true,
        needsAdvertise: true,
      );

      expect(status, BlePermissionStatus.grantedScanOnly);
    });
  });
}
