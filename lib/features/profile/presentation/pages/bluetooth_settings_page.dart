import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../../core/di/injection.dart';

/// Bluetooth settings page for managing BLE discovery preferences.
class BluetoothSettingsPage extends StatefulWidget {
  const BluetoothSettingsPage({super.key});

  @override
  State<BluetoothSettingsPage> createState() => _BluetoothSettingsPageState();
}

class _BluetoothSettingsPageState extends State<BluetoothSettingsPage> {
  final _bluetoothService = getIt<BluetoothService>();
  bool _isBluetoothEnabled = false;
  bool _hasPermissions = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);

    final bluetoothEnabled = await _bluetoothService.isBluetoothEnabled();

    // Android 12+ (API 31+): scan/connect/advertise are the only runtime perms.
    // iOS: Bluetooth permission only.
    bool hasBlePermissions;
    if (Platform.isAndroid) {
      final bluetoothScanStatus = await Permission.bluetoothScan.status;
      final bluetoothAdvertiseStatus =
          await Permission.bluetoothAdvertise.status;
      final bluetoothConnectStatus = await Permission.bluetoothConnect.status;

      hasBlePermissions = bluetoothScanStatus.isGranted &&
          bluetoothAdvertiseStatus.isGranted &&
          bluetoothConnectStatus.isGranted;
    } else if (Platform.isIOS) {
      hasBlePermissions = (await Permission.bluetooth.status).isGranted;
    } else {
      hasBlePermissions = false;
    }

    setState(() {
      _isBluetoothEnabled = bluetoothEnabled;
      _hasPermissions = hasBlePermissions;
      _isLoading = false;
    });
  }

  Future<void> _requestPermissions() async {
    late final Map<Permission, PermissionStatus> statuses;
    if (Platform.isAndroid) {
      statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ].request();
    } else if (Platform.isIOS) {
      statuses = await [Permission.bluetooth].request();
    } else {
      statuses = const {};
    }

    await _checkStatus();

    if (!mounted) return;

    final allGranted = statuses.values.every((status) => status.isGranted);
    if (allGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions granted')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Some permissions were denied. Please grant them in settings.'),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: openAppSettings,
          ),
        ),
      );
    }
  }

  Future<void> _toggleBluetooth() async {
    if (_isBluetoothEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please turn off Bluetooth manually in system settings'),
        ),
      );
    } else {
      await _bluetoothService.requestBluetoothOn();
      await _checkStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
              children: [
                // Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bluetooth,
                              color: _isBluetoothEnabled
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bluetooth Status',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _isBluetoothEnabled
                                        ? 'Enabled'
                                        : 'Disabled',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isBluetoothEnabled,
                              onChanged: (_) => _toggleBluetooth(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Permissions Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _hasPermissions
                                  ? Icons.check_circle
                                  : Icons.warning_amber_rounded,
                              color: _hasPermissions
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Permissions',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _hasPermissions
                                        ? 'All permissions granted'
                                        : 'Some permissions needed',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_hasPermissions)
                              TextButton(
                                onPressed: _requestPermissions,
                                child: const Text('Grant'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Information Section
                const Text(
                  'How Bluetooth Discovery Works',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const _InfoItem(
                  icon: Icons.radar,
                  title: 'BLE Scanning',
                  description:
                      'Your device scans for nearby Radius users using Bluetooth Low Energy. This uses minimal battery.',
                ),
                const _InfoItem(
                  icon: Icons.broadcast_on_personal,
                  title: 'BLE Advertising',
                  description:
                      'Your device broadcasts an anonymous ID so others can discover you. Your real identity is only revealed through the app.',
                ),
                const _InfoItem(
                  icon: Icons.security,
                  title: 'Privacy Protection',
                  description:
                      'Your anonymous ID rotates every 15 minutes for enhanced privacy. No personal information is shared via Bluetooth.',
                ),
                const _InfoItem(
                  icon: Icons.battery_charging_full,
                  title: 'Battery Optimized',
                  description:
                      'Discovery uses intermittent scanning (10s scan every 30s) to preserve battery life.',
                ),
              ],
            ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
