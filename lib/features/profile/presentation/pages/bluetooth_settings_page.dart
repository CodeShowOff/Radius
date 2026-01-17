import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/routes.dart';
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
  bool _scanPermissionGranted = false;
  bool _advertisePermissionGranted = false;
  bool _connectPermissionGranted = false;
  bool _isLoading = true;

  bool _keepDiscoveringInBackground = false;
  bool _useForegroundServiceForBackground = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _loadBackgroundDiscoveryPrefs();
  }

  Future<void> _loadBackgroundDiscoveryPrefs() async {
    if (!Platform.isAndroid) return;

    await _bluetoothService.refreshBackgroundDiscoveryPreferences();
    if (!mounted) return;
    setState(() {
      _keepDiscoveringInBackground =
          _bluetoothService.keepDiscoveringInBackground;
      _useForegroundServiceForBackground =
          _bluetoothService.useForegroundServiceForBackgroundDiscovery;
    });
  }

  Future<void> _setBackgroundDiscovery(bool enabled) async {
    if (!Platform.isAndroid) return;

    if (!enabled) {
      setState(() {
        _keepDiscoveringInBackground = false;
        _useForegroundServiceForBackground = false;
      });
      await _bluetoothService.setBackgroundDiscoveryPreference(
        enabled: false,
        useForegroundService: false,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Background discovery disabled')),
      );
      return;
    }

    final choice = await showDialog<_BackgroundDiscoveryChoice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Keep discovering in background?'),
          content: const Text(
            'This keeps scanning for nearby Radius users while the app is not on screen.\n\n'
            'It may increase battery usage. Foreground Service mode shows a persistent notification while discovery is active.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pop(_BackgroundDiscoveryChoice.pendingIntent),
              child: const Text('Use Background Scan'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context)
                  .pop(_BackgroundDiscoveryChoice.foregroundService),
              child: const Text('Use Foreground Service'),
            ),
          ],
        );
      },
    );

    if (choice == null) return;

    final useFgs = choice == _BackgroundDiscoveryChoice.foregroundService;
    setState(() {
      _keepDiscoveringInBackground = true;
      _useForegroundServiceForBackground = useFgs;
    });

    await _bluetoothService.setBackgroundDiscoveryPreference(
      enabled: true,
      useForegroundService: useFgs,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          useFgs
              ? 'Background discovery enabled (Foreground Service)'
              : 'Background discovery enabled',
        ),
      ),
    );
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

      final scanGranted = bluetoothScanStatus.isGranted;
      final advertiseGranted = bluetoothAdvertiseStatus.isGranted;
      final connectGranted = bluetoothConnectStatus.isGranted;

      _scanPermissionGranted = scanGranted;
      _advertisePermissionGranted = advertiseGranted;
      _connectPermissionGranted = connectGranted;

      // Full discovery (scan + advertise) needs all three.
      // Scan-only and advertise-only flows are handled elsewhere in the app.
      hasBlePermissions = scanGranted && advertiseGranted && connectGranted;
    } else if (Platform.isIOS) {
      final granted = (await Permission.bluetooth.status).isGranted;
      _scanPermissionGranted = granted;
      _advertisePermissionGranted = granted;
      _connectPermissionGranted = granted;
      hasBlePermissions = granted;
    } else {
      _scanPermissionGranted = false;
      _advertisePermissionGranted = false;
      _connectPermissionGranted = false;
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
      final permissionsToRequest = <Permission>[];

      final scanStatus = await Permission.bluetoothScan.status;
      final advertiseStatus = await Permission.bluetoothAdvertise.status;
      final connectStatus = await Permission.bluetoothConnect.status;

      if (!scanStatus.isGranted) {
        permissionsToRequest.add(Permission.bluetoothScan);
      }
      if (!advertiseStatus.isGranted) {
        permissionsToRequest.add(Permission.bluetoothAdvertise);
      }
      if (!connectStatus.isGranted) {
        permissionsToRequest.add(Permission.bluetoothConnect);
      }

      if (permissionsToRequest.isEmpty) {
        statuses = const {};
      } else {
        statuses = await permissionsToRequest.request();
      }
    } else if (Platform.isIOS) {
      statuses = await [Permission.bluetooth].request();
    } else {
      statuses = const {};
    }

    await _checkStatus();

    if (!mounted) return;

    final allGranted =
        statuses.isEmpty || statuses.values.every((status) => status.isGranted);
    if (allGranted && _scanPermissionGranted && _connectPermissionGranted) {
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
                                        : 'Some permissions are missing',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (Platform.isAndroid)
                                    Text(
                                      'Scan: ${_scanPermissionGranted ? 'granted' : 'missing'} · '
                                      'Advertise: ${_advertisePermissionGranted ? 'granted' : 'missing'} · '
                                      'Connect: ${_connectPermissionGranted ? 'granted' : 'missing'}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (Platform.isAndroid &&
                                      _scanPermissionGranted &&
                                      _connectPermissionGranted &&
                                      !_advertisePermissionGranted) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Advertising disabled (permission denied) — scanning still active',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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

                if (Platform.isAndroid) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.nightlight_round,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Background Discovery',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Keep scanning while the app is in background (Android only).',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Keep discovering in background'),
                            subtitle: Text(
                              _keepDiscoveringInBackground
                                  ? (_useForegroundServiceForBackground
                                      ? 'Mode: Foreground Service (persistent notification)'
                                      : 'Mode: System background scan (PendingIntent)')
                                  : 'Off',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 12,
                              ),
                            ),
                            value: _keepDiscoveringInBackground,
                            onChanged: _setBackgroundDiscovery,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Diagnostics
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bug_report_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Diagnostics Logs',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                context.push(Routes.diagnosticsLogs);
                              },
                              child: const Text('Open'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Stores detailed Bluetooth/Nearby logs on this device so you can share them for troubleshooting.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
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

enum _BackgroundDiscoveryChoice {
  pendingIntent,
  foregroundService,
}
