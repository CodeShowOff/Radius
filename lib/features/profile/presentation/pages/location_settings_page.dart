import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Location settings page for managing location permissions and preferences.
/// Used for SOS Nearby Help feature.
class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({super.key});

  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  bool _isLocationEnabled = false;
  bool _hasPermission = false;
  bool _hasBackgroundPermission = false;
  bool _isLoading = true;
  int _androidSdkVersion = 0;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);

    final locationEnabled = await Geolocator.isLocationServiceEnabled();
    final permissionStatus = await Permission.location.status;
    final backgroundStatus = await Permission.locationAlways.status;

    // Get Android SDK version for proper background location handling
    int sdkVersion = 0;
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        sdkVersion = androidInfo.version.sdkInt;
      } catch (_) {
        // Default to a safe value if we can't get SDK version
        sdkVersion = 30;
      }
    }

    setState(() {
      _isLocationEnabled = locationEnabled;
      _hasPermission = permissionStatus.isGranted;
      _hasBackgroundPermission = backgroundStatus.isGranted;
      _androidSdkVersion = sdkVersion;
      _isLoading = false;
    });
  }

  Future<void> _requestPermission() async {
    final status = await Permission.location.request();

    await _checkStatus();

    if (!mounted) return;

    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission granted')),
      );
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Location permission denied. Please grant it in settings.'),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: openAppSettings,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location permission denied'),
        ),
      );
    }
  }

  Future<void> _requestBackgroundPermission() async {
    // First ensure we have foreground permission
    if (!_hasPermission) {
      await _requestPermission();
      if (!_hasPermission) return;
    }

    // On Android 11+ (API 30+), background location cannot be requested via dialog
    // User must be directed to app settings to enable "Allow all the time"
    if (Platform.isAndroid && _androidSdkVersion >= 30) {
      // Show educational dialog explaining why background location is needed
      // and how to enable it in settings
      if (!mounted) return;
      
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Background Location Required'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To allow helpers to navigate to you even when the app is minimized, '
                'please enable background location access.',
              ),
              SizedBox(height: 16),
              Text(
                'In Settings, select:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Location â†’ Allow all the time'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not Now'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
        // Wait a bit then recheck status when user returns
        await Future.delayed(const Duration(seconds: 1));
        await _checkStatus();
      }
      return;
    }

    // On Android 10 and below, or iOS, we can request permission directly
    final status = await Permission.locationAlways.request();

    await _checkStatus();

    if (!mounted) return;

    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Background location permission granted')),
      );
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Background location permission denied. Please grant it in settings.'),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: openAppSettings,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Background location permission denied'),
        ),
      );
    }
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
    // Recheck status when user returns
    await Future.delayed(const Duration(seconds: 1));
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Location Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding + 24),
              children: [
                // Location Service Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: _isLocationEnabled
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Location Services',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _isLocationEnabled ? 'Enabled' : 'Disabled',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isLocationEnabled)
                              TextButton(
                                onPressed: _openLocationSettings,
                                child: const Text('Enable'),
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
                              _hasPermission
                                  ? Icons.check_circle
                                  : Icons.warning_amber_rounded,
                              color: _hasPermission
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Location Permission',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    _hasPermission
                                        ? 'Permission granted'
                                        : 'Permission not granted',
                                    style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_hasPermission)
                              TextButton(
                                onPressed: _requestPermission,
                                child: const Text('Grant'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Background Location Permission Card (optional, for enhanced features)
                if (Platform.isAndroid || Platform.isIOS)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _hasBackgroundPermission
                                    ? Icons.check_circle
                                    : Icons.info_outline,
                                color: _hasBackgroundPermission
                                    ? Theme.of(context).colorScheme.tertiary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Background Location',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      _hasBackgroundPermission
                                          ? 'Permission granted'
                                          : 'Optional - for enhanced features',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_hasBackgroundPermission)
                                TextButton(
                                  onPressed: _requestBackgroundPermission,
                                  child: const Text('Grant'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Background location allows helpers to navigate to you even when the app is minimized.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Information Section
                const Text(
                  'How Location is Used',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const _InfoItem(
                  icon: Icons.sos,
                  title: 'SOS Nearby Help',
                  description:
                      'Your location is shared with nearby helpers when you create an SOS request, allowing them to navigate to your location.',
                ),
                const _InfoItem(
                  icon: Icons.navigation,
                  title: 'Helper Navigation',
                  description:
                      'When you respond to help someone, your location is used to provide directions to the person in need.',
                ),
                const _InfoItem(
                  icon: Icons.security,
                  title: 'Privacy Protection',
                  description:
                      'Your location is only shared when you explicitly create or respond to a help request. It is not tracked or stored otherwise.',
                ),
                const _InfoItem(
                  icon: Icons.battery_saver,
                  title: 'Battery Efficient',
                  description:
                      'Location is only accessed when needed for SOS features. Background location is optional and only used during active help sessions.',
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
