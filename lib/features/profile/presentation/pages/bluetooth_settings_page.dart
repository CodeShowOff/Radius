import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../../core/settings/app_settings_store.dart';
import '../../../../core/di/injection.dart';
import '../../../proximity/proximity_service.dart';

/// Bluetooth settings page for managing BLE discovery preferences.
class BluetoothSettingsPage extends StatefulWidget {
  const BluetoothSettingsPage({super.key});

  @override
  State<BluetoothSettingsPage> createState() => _BluetoothSettingsPageState();
}

class _BluetoothSettingsPageState extends State<BluetoothSettingsPage>
    with WidgetsBindingObserver, RouteAware {
  final _bluetoothService = getIt<BluetoothService>();
  final _settingsStore = getIt<AppSettingsStore>();
  final _proximityService = getIt<ProximityService>();
  bool _isBluetoothEnabled = false;
  bool _hasPermissions = false;
  bool _scanPermissionGranted = false;
  bool _advertisePermissionGranted = false;
  bool _backgroundAdvertising = false;
  bool _isLoading = true;
  bool _permissionRevokedWarning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    final modalRoute = ModalRoute.of(context);
    if (modalRoute is PageRoute) {
      getIt<RouteObserver<PageRoute>>().subscribe(this, modalRoute);
    }
  }

  @override
  void dispose() {
    getIt<RouteObserver<PageRoute>>().unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-check permissions when app resumes to detect runtime revocation
    if (state == AppLifecycleState.resumed) {
      _checkStatus();
    }
  }

  @override
  void didPopNext() {
    // Called when returning to this route from another route
    // Re-check status to sync with Home page
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);

    // Save previous state BEFORE checking new permissions
    final previousAdvertiseGranted = _advertisePermissionGranted;
    final wasBackgroundAdvOn = _backgroundAdvertising;

    final bluetoothEnabled = await _bluetoothService.isBluetoothEnabled();

    // Android 12+ (API 31+): scan/connect/advertise are the only runtime perms.
    // iOS: Bluetooth permission only.
    bool hasBlePermissions;
    bool scanGranted = false;
    bool advertiseGranted = false;

    if (Platform.isAndroid) {
      final bluetoothScanStatus = await Permission.bluetoothScan.status;
      final bluetoothAdvertiseStatus =
          await Permission.bluetoothAdvertise.status;

      scanGranted = bluetoothScanStatus.isGranted;
      advertiseGranted = bluetoothAdvertiseStatus.isGranted;

      _scanPermissionGranted = scanGranted;
      _advertisePermissionGranted = advertiseGranted;

      // Foreground discovery requires SCAN. Advertising is optional.
      // BLUETOOTH_CONNECT is only required for GATT connections (not used for scanning).
      hasBlePermissions = scanGranted;
    } else if (Platform.isIOS) {
      final granted = (await Permission.bluetooth.status).isGranted;
      scanGranted = granted;
      advertiseGranted = granted;

      _scanPermissionGranted = granted;
      _advertisePermissionGranted = granted;
      hasBlePermissions = granted;
    } else {
      _scanPermissionGranted = false;
      _advertisePermissionGranted = false;
      hasBlePermissions = false;
    }

    final bgAdv = _settingsStore.getBackgroundAdvertising();

    // Detect runtime permission revocation while background advertising is enabled
    final permissionRevoked = Platform.isAndroid &&
        previousAdvertiseGranted &&
        !advertiseGranted &&
        wasBackgroundAdvOn &&
        bgAdv;

    // Auto-disable background advertising if permission was revoked
    if (permissionRevoked && !_isLoading) {
      await _proximityService.setBackgroundAdvertising(false);
    }

    setState(() {
      _isBluetoothEnabled = bluetoothEnabled;
      _hasPermissions = hasBlePermissions;
      _backgroundAdvertising = permissionRevoked ? false : bgAdv;
      _permissionRevokedWarning = permissionRevoked;
      _isLoading = false;
    });

    // Show warning if permission was revoked
    if (permissionRevoked && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Bluetooth Advertise permission was revoked. Background advertising has been disabled.',
          ),
          action: SnackBarAction(
            label: 'Grant',
            onPressed: _requestPermissions,
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _requestPermissions() async {
    late final Map<Permission, PermissionStatus> statuses;
    if (Platform.isAndroid) {
      final permissionsToRequest = <Permission>[];

      final scanStatus = await Permission.bluetoothScan.status;
      final advertiseStatus = await Permission.bluetoothAdvertise.status;

      if (!scanStatus.isGranted) {
        permissionsToRequest.add(Permission.bluetoothScan);
      }
      if (!advertiseStatus.isGranted) {
        permissionsToRequest.add(Permission.bluetoothAdvertise);
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
    if (allGranted && _scanPermissionGranted) {
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
        title: const Text(
          'Bluetooth Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
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
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.error,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (Platform.isAndroid)
                                    Text(
                                      'Scan: ${_scanPermissionGranted ? 'granted' : 'missing'} Â· '
                                      'Advertise: ${_advertisePermissionGranted ? 'granted' : 'missing'}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                  if (Platform.isAndroid &&
                                      _scanPermissionGranted &&
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
                                              .onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Advertising disabled (permission denied) â€” scanning still active',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
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

                // Background Advertising Toggle Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.broadcast_on_personal,
                              color: _backgroundAdvertising
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Background Advertising',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _backgroundAdvertising
                                        ? 'Stays on when app is closed'
                                        : 'Stops when app is closed',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _backgroundAdvertising,
                              onChanged: (_hasPermissions &&
                                      _advertisePermissionGranted)
                                  ? (value) async {
                                      setState(
                                          () => _backgroundAdvertising = value);
                                      await _proximityService
                                          .setBackgroundAdvertising(value);
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When enabled, your device keeps advertising your username via Bluetooth even after the app is closed or removed from recents. '
                          'This uses a lightweight background service and minimal battery.',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        if (_permissionRevokedWarning) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Permission was revoked. Background advertising disabled.',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

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
                                  'Discovery Mode',
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
                            'Scanning runs for 15 seconds when you tap "Find People Nearby". '
                            'Advertising ${_backgroundAdvertising ? 'keeps running even when the app is closed (background mode on)' : 'runs while the app is open (enable Background Advertising above to keep it running)'}.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                      'Your device broadcasts your username so nearby Radius users can discover you. Only connected users can chat with you.',
                ),
                const _InfoItem(
                  icon: Icons.security,
                  title: 'Privacy Protection',
                  description:
                      'Only your username is visible via Bluetooth for discovery. You control who can connect and chat with you.',
                ),
                const _InfoItem(
                  icon: Icons.battery_charging_full,
                  title: 'Battery Optimized',
                  description:
                      'BLE uses minimal power. Scanning runs for 15 seconds on demand. Advertising is lightweight and battery-efficient.',
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
