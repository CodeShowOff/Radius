import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/utils/chat_utils.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../../profile/presentation/widgets/mood_selector.dart';
import '../../domain/entities/nearby_user.dart';
import '../bloc/nearby_users_bloc.dart';
import '../widgets/ble_diagnostics_panel.dart';
import '../widgets/nearby_user_card.dart';
import '../widgets/nearby_users_empty_state.dart';

/// Screen displaying nearby users discovered via BLE.
///
/// - Advertising is started app-wide when user authenticates (to be discoverable)
/// - If Bluetooth is off, waits until Bluetooth is turned on before advertising
/// - Scanning starts when user taps "Scan" button (runs for 10 seconds, shows results in real-time)
/// - Scanning stops when app goes to background
/// - Page shows faded content with prominent "Turn On Bluetooth" button when Bluetooth is off
class NearbyUsersScreen extends StatefulWidget {
  const NearbyUsersScreen({super.key});

  @override
  State<NearbyUsersScreen> createState() => _NearbyUsersScreenState();
}

class _NearbyUsersScreenState extends State<NearbyUsersScreen>
    with WidgetsBindingObserver {
  bool _scanPermissionGranted = false;
  bool _connectPermissionGranted = false;
  bool _blePermissionsLoaded = false;
  bool _bleRationaleShownThisSession = false;
  bool _bluetoothEnabled = false;
  bool _checkingBluetooth = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshBlePermissions());
    unawaited(_checkBluetoothStatus());
    // Ensure advertising is running when screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAdvertisingRunning();
    });
  }

  @override
  void deactivate() {
    // Stop scanning when leaving the screen
    try {
      context.read<NearbyUsersBloc>().add(const NearbyUsersStopScan());
    } catch (_) {}
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      context.read<NearbyUsersBloc>().add(const NearbyUsersStopScan());
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bloc = context.read<NearbyUsersBloc>();

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Stop scanning when app goes to background
      bloc.add(const NearbyUsersAppBackgrounded());
      return;
    }

    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshBlePermissions());
      unawaited(_checkBluetoothStatus());
      bloc.add(const NearbyUsersAppResumed());
      // Also ensure advertising is running when app resumes
      _ensureAdvertisingRunning();
    }
  }

  /// Ensures advertising is running when screen is visible.
  void _ensureAdvertisingRunning() {
    try {
      final bloc = context.read<NearbyUsersBloc>();
      final state = bloc.state;

      // If not advertising, trigger restart
      if (!state.isAdvertising) {
        bloc.add(const NearbyUsersAppResumed());
      }
    } catch (_) {
      // Ignore if bloc is not available
    }
  }

  Future<bool> _maybeShowBleRationale() async {
    if (_bleRationaleShownThisSession) return true;
    if (kIsWeb) return true;
    if (!mounted) return false;

    // Only show on Android when one of the runtime permissions is missing.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final scanGranted = await Permission.bluetoothScan.isGranted;
      final connectGranted = await Permission.bluetoothConnect.isGranted;
      final advertiseGranted = await Permission.bluetoothAdvertise.isGranted;

      if (scanGranted && connectGranted && advertiseGranted) {
        _bleRationaleShownThisSession = true;
        return true;
      }
    } else {
      // iOS or other platforms: keep it lightweight.
      _bleRationaleShownThisSession = true;
      return true;
    }

    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Bluetooth permission'),
          content: const Text(
            'Radius uses Bluetooth to discover nearby users. Next, Android will ask for Bluetooth permissions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    _bleRationaleShownThisSession = true;
    return confirmed ?? false;
  }

  Future<void> _checkBluetoothStatus() async {
    setState(() => _checkingBluetooth = true);
    try {
      final bluetoothService = context.read<BluetoothService>();
      final isEnabled = await bluetoothService.isBluetoothEnabled();
      if (mounted) {
        final wasDisabled = !_bluetoothEnabled;
        setState(() {
          _bluetoothEnabled = isEnabled;
          _checkingBluetooth = false;
        });
        
        // If Bluetooth just turned on, clear any Bluetooth-related errors
        if (wasDisabled && isEnabled) {
          final bloc = context.read<NearbyUsersBloc>();
          final state = bloc.state;
          final errorMessage = state.errorMessage?.toLowerCase() ?? '';
          final isBluetoothError = errorMessage.contains('bluetooth');
          
          if (isBluetoothError && state.status == NearbyUsersStatus.error) {
            // Clear the error by resetting to idle state
            bloc.add(const NearbyUsersClearResults());
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bluetoothEnabled = false;
          _checkingBluetooth = false;
        });
      }
    }
  }

  Future<void> _requestBluetoothOn() async {
    try {
      final bluetoothService = context.read<BluetoothService>();
      await bluetoothService.requestBluetoothOn();
      // Wait a bit for Bluetooth to turn on
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkBluetoothStatus();
      // Ensure advertising starts after Bluetooth is on
      _ensureAdvertisingRunning();
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _startScan() async {
    // Check if Bluetooth is on first
    if (!_bluetoothEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please turn on Bluetooth first'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    
    final okToProceed = await _maybeShowBleRationale();
    if (!okToProceed) return;
    if (!mounted) return;

    context.read<NearbyUsersBloc>().add(const NearbyUsersStartScan());
  }

  void _stopScan() {
    context.read<NearbyUsersBloc>().add(const NearbyUsersStopScan());
  }

  Future<void> _refreshBlePermissions() async {
    // Avoid dart:io (web builds). permission_handler supports non-web platforms.
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _scanPermissionGranted = false;
        _connectPermissionGranted = false;
        _blePermissionsLoaded = true;
      });
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      if (!mounted) return;
      setState(() {
        // iOS uses a single Bluetooth permission; this banner is Android-specific.
        _scanPermissionGranted = true;
        _connectPermissionGranted = true;
        _blePermissionsLoaded = true;
      });
      return;
    }

    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;

    if (!mounted) return;
    setState(() {
      _scanPermissionGranted = scanStatus.isGranted;
      _connectPermissionGranted = connectStatus.isGranted;
      _blePermissionsLoaded = true;
    });
  }

  Future<void> _showHowItWorks() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // Prevent RenderFlex overflows on small devices.
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How Nearby works',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Radius uses Bluetooth Low Energy (BLE) to scan for nearby users and (optionally) advertise an anonymous ID.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  const _HowItWorksBullet(
                    title: 'Foreground-only',
                    body:
                        'Discovery runs only while the app is open and this screen is visible. Background discovery is disabled to save battery and protect privacy.',
                  ),
                  const _HowItWorksBullet(
                    title: 'Some phones need extra steps',
                    body:
                        'On some Android phones, battery/"app sleep" features can still reduce BLE discovery reliability. Use Troubleshooting for device-specific tips.',
                  ),
                  const _HowItWorksBullet(
                    title: 'Privacy',
                    body:
                        'Your Bluetooth broadcast uses a rotating anonymous ID. No personal info is shared over Bluetooth.',
                  ),
                  const _HowItWorksBullet(
                    title: 'Permissions',
                    body:
                        'To discover nearby users, allow Bluetooth when prompted. If you denied it, you can enable it in Settings.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            unawaited(_showTroubleshooting());
                          },
                          child: const Text('Troubleshooting'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<_AndroidDeviceSummary?> _getAndroidDeviceSummary() async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _AndroidDeviceSummary(
        manufacturer: info.manufacturer.trim(),
        brand: info.brand.trim(),
        model: info.model.trim(),
        sdkInt: info.version.sdkInt,
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _oemGuidanceFor(_AndroidDeviceSummary? d) {
    final manufacturer = (d?.manufacturer ?? '').toLowerCase();
    final brand = (d?.brand ?? '').toLowerCase();

    final key = manufacturer.isNotEmpty ? manufacturer : brand;

    // Keep these short and actionable; users can follow them in Settings.
    if (key.contains('xiaomi') ||
        key.contains('redmi') ||
        key.contains('poco')) {
      return const [
        'Set Battery saver for Radius to â€œNo restrictionsâ€.',
        'Enable Autostart for Radius (if available).',
        'Lock Radius in Recents (tap the app icon â†’ Lock).',
      ];
    }

    if (key.contains('huawei') || key.contains('honor')) {
      return const [
        'Battery: set Radius to â€œNot allowed to optimizeâ€.',
        'App launch: manage manually; allow auto-launch + background activity.',
      ];
    }

    if (key.contains('samsung')) {
      return const [
        'Battery: set Radius to â€œUnrestrictedâ€ (or disable â€œPut unused apps to sleepâ€ for it).',
        'Ensure Bluetooth is allowed while the Nearby screen is open.',
      ];
    }

    if (key.contains('oppo') ||
        key.contains('realme') ||
        key.contains('vivo')) {
      return const [
        'Allow background activity / disable app sleep for Radius.',
        'Battery: set Radius to â€œDonâ€™t optimizeâ€ (or â€œNo restrictionsâ€).',
      ];
    }

    if (key.contains('oneplus')) {
      return const [
        'Battery optimization: set Radius to â€œDonâ€™t optimizeâ€.',
        'Disable aggressive sleep/hibernation for Radius if available.',
      ];
    }

    return const [
      'Battery optimization: set Radius to â€œDonâ€™t optimizeâ€ / â€œUnrestrictedâ€ if available.',
      'Keep Radius open on the Nearby screen during discovery.',
    ];
  }

  Future<void> _showTroubleshooting() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Troubleshooting',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you see â€œno nearby usersâ€ even when phones are close, this is often caused by permissions, Bluetooth being off, or OEM battery management.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<_AndroidDeviceSummary?>(
                    future: _getAndroidDeviceSummary(),
                    builder: (context, snap) {
                      final summary = snap.data;
                      if (defaultTargetPlatform != TargetPlatform.android) {
                        return const SizedBox.shrink();
                      }

                      final title = summary == null
                          ? 'Android device'
                          : 'Android device: ${summary.manufacturer.isEmpty ? summary.brand : summary.manufacturer} ${summary.model}'
                              .trim();
                      final steps = _oemGuidanceFor(summary);

                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: theme.textTheme.titleSmall),
                              const SizedBox(height: 8),
                              for (final s in steps)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('â€¢ '),
                                      Expanded(child: Text(s)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await openAppSettings();
                                    },
                                    icon: const Icon(Icons.settings_outlined),
                                    label: const Text('Open app settings'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tips', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          const Text('â€¢ Make sure Bluetooth is turned on'),
                          const Text('â€¢ Grant all Bluetooth permissions'),
                          const Text(
                              'â€¢ Disable battery optimization for this app'),
                          const Text(
                              'â€¢ Keep the app in foreground while scanning'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _shouldShowPermissionCtaBanner(NearbyUsersState state) {
    if (kIsWeb) return false;

    final message = state.errorMessage?.toLowerCase() ?? '';
    final hasPermissionError =
        message.contains('permission') || message.contains('permissions');

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!_blePermissionsLoaded) return false;
      final missingRuntime =
          !_scanPermissionGranted || !_connectPermissionGranted;
      return missingRuntime || hasPermissionError;
    }

    // iOS/other platforms: only show when we have a permission-related error.
    return hasPermissionError;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nearby',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Help',
            icon: const Icon(Icons.info_outline),
            onPressed: () => unawaited(_showHowItWorks()),
          ),
          if (kDebugMode)
            IconButton(
              tooltip: 'Diagnostics logs',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => context.push(Routes.diagnosticsLogs),
            ),
        ],
      ),
      body: BlocConsumer<NearbyUsersBloc, NearbyUsersState>(
        listenWhen: (prev, curr) =>
            curr.status == NearbyUsersStatus.error &&
            prev.errorMessage != curr.errorMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () async {
                    await openAppSettings();
                    await _refreshBlePermissions();
                  },
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              // Bluetooth status banner
              if (!_bluetoothEnabled && !_checkingBluetooth)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.bluetooth_disabled,
                            color: theme.colorScheme.error,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bluetooth is Off',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Turn on Bluetooth to discover nearby users',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _requestBluetoothOn,
                              icon: const Icon(Icons.bluetooth),
                              label: const Text('Turn On Bluetooth'),
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                                foregroundColor: theme.colorScheme.onError,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _checkBluetoothStatus,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Header card with scan button (faded when Bluetooth is off)
              Opacity(
                opacity: _bluetoothEnabled ? 1.0 : 0.4,
                child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Discover nearby users',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.isScanning
                                    ? 'Scanning for 10 seconds...'
                                    : state.isAdvertising
                                        ? 'You are visible to nearby users'
                                        : 'Tap Scan to find nearby users',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Scan/Stop button
                        if (state.isScanning)
                          FilledButton.tonalIcon(
                            onPressed: _stopScan,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.radar),
                            label: const Text('Scan'),
                          ),
                      ],
                    ),
                    // Progress indicator during scan
                    if (state.isScanning) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(),
                      ),
                    ],
                  ],
                ),
              ),
              ),

              // Permission banner (faded when Bluetooth is off)
              if (_shouldShowPermissionCtaBanner(state))
                Opacity(
                  opacity: _bluetoothEnabled ? 1.0 : 0.4,
                  child:
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 20,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bluetooth permission required',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await openAppSettings();
                          await _refreshBlePermissions();
                        },
                        child: const Text('Settings'),
                      ),
                    ],
                  ),
                ),
                ),

              // Main content (faded when Bluetooth is off)
              Expanded(
                child: Opacity(
                  opacity: _bluetoothEnabled ? 1.0 : 0.4,
                  child: _buildContent(context, state),
                ),
              ),

              // Status panel at bottom with safe padding
              Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom,
                ),
                child: const BleDiagnosticsPanel(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, NearbyUsersState state) {
    Widget content;

    switch (state.status) {
      case NearbyUsersStatus.loading:
        content = const Center(
          child: CircularProgressIndicator(),
        );
        break;

      case NearbyUsersStatus.error:
        // Don't show error state if it's just Bluetooth being off
        // (we already show the banner for that)
        final errorMessage = state.errorMessage?.toLowerCase() ?? '';
        final isBluetoothOffError = errorMessage.contains('bluetooth') && 
                                     errorMessage.contains('off');
        
        if (isBluetoothOffError || !_bluetoothEnabled) {
          // Show empty state instead of error when Bluetooth is off
          content = NearbyUsersEmptyState(
            isScanning: false,
            hasSearchedAwhile: false,
            onRetry: _startScan,
          );
        } else {
          content = _ErrorState(
            message: state.errorMessage ?? 'An error occurred',
            onRetry: _startScan,
          );
        }
        break;

      case NearbyUsersStatus.idle:
        content = NearbyUsersEmptyState(
          isScanning: false,
          hasSearchedAwhile: false,
          onRetry: _startScan,
        );
        break;

      case NearbyUsersStatus.scanning:
        content = _ScanningState(
          userCount: state.users.length,
        );
        break;

      case NearbyUsersStatus.empty:
        content = NearbyUsersEmptyState(
          isScanning: false,
          hasSearchedAwhile: true,
          onRetry: _startScan,
        );
        break;

      case NearbyUsersStatus.results:
        content = _NearbyUsersList(
          users: state.users,
          isDiscovering: false,
        );
        break;
    }

    return content;
  }
}

/// Widget shown during scanning
class _ScanningState extends StatelessWidget {
  final int userCount;

  const _ScanningState({required this.userCount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            'Scanning for nearby users...',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            userCount == 0
                ? 'Looking for devices'
                : 'Found $userCount ${userCount == 1 ? 'user' : 'users'} so far',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AndroidDeviceSummary {
  final String manufacturer;
  final String brand;
  final String model;
  final int sdkInt;

  const _AndroidDeviceSummary({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.sdkInt,
  });
}

class _HowItWorksBullet extends StatelessWidget {
  final String title;
  final String body;

  const _HowItWorksBullet({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nearby users list with smooth scrolling and mood filtering.
class _NearbyUsersList extends StatefulWidget {
  final List<NearbyUser> users;
  final bool isDiscovering;

  const _NearbyUsersList({
    required this.users,
    required this.isDiscovering,
  });

  @override
  State<_NearbyUsersList> createState() => _NearbyUsersListState();
}

class _NearbyUsersListState extends State<_NearbyUsersList> {
  String? _selectedMoodFilter;
  String? _selectedGenderFilter;

  static const moods = {
    'ðŸ˜Š Chill': 'ðŸ˜Š Chill',
    'ðŸ¤“ Focused': 'ðŸ¤“ Focused',
    'ðŸ§  Deep talk': 'ðŸ§  Deep talk',
    'ðŸ˜‚ Fun': 'ðŸ˜‚ Fun',
  };

  static const genders = {
    'ðŸ‘¨ Male': 'Male',
    'ðŸ‘© Female': 'Female',
    'âš§ï¸ Non-binary': 'Non-binary',
    'ðŸ¤· Prefer not to say': 'Prefer not to say',
  };

  List<NearbyUser> get _filteredUsers {
    var filtered = widget.users;

    // Apply mood filter - only include users with exact matching mood (trimmed and compared)
    if (_selectedMoodFilter != null) {
      filtered = filtered.where((user) {
        final userMood = user.mood?.trim();
        final filterMood = _selectedMoodFilter?.trim();
        return userMood != null && userMood == filterMood;
      }).toList();
    }

    // Apply gender filter - only include users with exact matching gender (trimmed and compared)
    if (_selectedGenderFilter != null) {
      filtered = filtered.where((user) {
        final userGender = user.gender?.trim();
        final filterGender = _selectedGenderFilter?.trim();
        return userGender != null && userGender == filterGender;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredUsers = _filteredUsers;

    return Column(
      children: [
        // Mood selector and filter chips
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick mood setter
              const MoodSelector(showLabel: false, compact: true),
              const SizedBox(height: 16),
              
              // Divider
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 8),
              
              // Filters header
              Text(
                'FILTERS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              
              // Mood filter section
              Row(
                children: [
                  Text(
                    'Mood:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: _selectedMoodFilter == null,
                            onSelected: (selected) {
                              setState(() {
                                _selectedMoodFilter = null;
                              });
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                          ),
                          const SizedBox(width: 8),
                          ...moods.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(entry.key),
                                selected: _selectedMoodFilter == entry.value,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedMoodFilter =
                                        selected ? entry.value : null;
                                  });
                                },
                                selectedColor:
                                    theme.colorScheme.secondaryContainer,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Gender filter section
              Row(
                children: [
                  Text(
                    'Gender:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: _selectedGenderFilter == null,
                            onSelected: (selected) {
                              setState(() {
                                _selectedGenderFilter = null;
                              });
                            },
                            selectedColor: theme.colorScheme.primaryContainer,
                          ),
                          const SizedBox(width: 8),
                          ...genders.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(entry.key),
                                selected: _selectedGenderFilter == entry.value,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedGenderFilter =
                                        selected ? entry.value : null;
                                  });
                                },
                                selectedColor:
                                    theme.colorScheme.tertiaryContainer,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // User list
        Expanded(
          child: filteredUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No users match the selected filters',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedMoodFilter = null;
                            _selectedGenderFilter = null;
                          });
                        },
                        child: const Text('Clear all filters'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    final bloc = context.read<NearbyUsersBloc>();
                    final authState = context.read<AuthBloc>().state;
                    if (authState is AuthAuthenticated) {
                      bloc.add(const NearbyUsersRefresh());

                      // Keep the indicator visible briefly.
                      await Future.delayed(const Duration(seconds: 2));
                    }
                  },
                  child: ListView.builder(
                    // Performance optimizations
                    itemCount: filteredUsers.length + 1, // +1 for footer
                    itemExtent: null, // Let items size themselves
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.only(top: 8, bottom: 100),
                    itemBuilder: (context, index) {
                      if (index == filteredUsers.length) {
                        // Footer with count
                        return _ListFooter(
                          count: filteredUsers.length,
                          isScanning: widget.isDiscovering,
                        );
                      }

                      final user = filteredUsers[index];

                      // Use RepaintBoundary for smoother scrolling
                      // Wrap with BlocBuilder to react to connection state changes
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(user.userId),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 400 + (index * 40)),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(30 * (1 - value), 0),
                            child: Opacity(
                              opacity: value,
                              child: Transform.scale(
                                scale: 0.95 + (0.05 * value),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: RepaintBoundary(
                          child: BlocBuilder<ConnectionBloc,
                              ConnectionBlocState>(
                            buildWhen: (previous, current) {
                              // Rebuild when connection state changes for this user
                              final prevState =
                                  previous.getStateForUser(user.userId ?? '');
                              final currState =
                                  current.getStateForUser(user.userId ?? '');
                              return prevState != currState;
                            },
                            builder: (context, connectionState) {
                              return NearbyUserCard(
                                key: ValueKey(user.username),
                                user: user,
                                onTap: () => _showUserDetails(context, user),
                                onConnect: user.isConnected
                                    ? null
                                    : () => _connectWithUser(context, user),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _showUserDetails(BuildContext context, NearbyUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserDetailsSheet(user: user),
    );
  }

  void _connectWithUser(BuildContext context, NearbyUser user) {
    // Get current user info
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to send connection requests'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Get receiver's user ID
    final receiverId = user.userId;
    if (receiverId == null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot connect: User ID not available'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if request already sent or processing
    final connectionState = context.read<ConnectionBloc>().state;
    if (connectionState.getSentRequestTo(receiverId) != null ||
        connectionState.getStateForUser(receiverId) == UserConnectionState.requestSent ||
        (connectionState.isActionLoading && connectionState.processingId == receiverId)) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request already sent'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Get sender's profile info
    final profileState = context.read<ProfileBloc>().state;
    String? senderDisplayName;
    String? senderPhotoUrl;
    if (profileState is ProfileLoaded) {
      senderDisplayName = profileState.profile.name;
      senderPhotoUrl = profileState.profile.photoUrl;
    }

    // Set current user info on the ConnectionBloc
    context.read<ConnectionBloc>().setCurrentUser(
          userId: authState.user.id,
          displayName: senderDisplayName,
          photoUrl: senderPhotoUrl,
        );

    // Send connection request
    context.read<ConnectionBloc>().add(ConnectionSendRequest(
          receiverId: receiverId,
          source: 'nearby',
          receiverDisplayName: user.displayName,
          receiverPhotoUrl: user.photoUrl,
        ));

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Connection request sent to ${user.displayName ?? 'user'}'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// List footer showing count and scanning status.
class _ListFooter extends StatelessWidget {
  final int count;
  final bool isScanning;

  const _ListFooter({
    required this.count,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            '$count ${count == 1 ? 'person' : 'people'} nearby',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (isScanning) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Scanning...',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Error state widget.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Check if error message suggests Bluetooth or permission issue
    final isBluetoothOrPermissionIssue =
        message.toLowerCase().contains('bluetooth') ||
            message.toLowerCase().contains('permission') ||
            message.toLowerCase().contains('location');

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
                if (isBluetoothOrPermissionIssue) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await openAppSettings();
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet showing user details.
class _UserDetailsSheet extends StatelessWidget {
  final NearbyUser user;

  const _UserDetailsSheet({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Avatar
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          (user.displayName ?? 'U')[0].toUpperCase(),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // Name
              Center(
                child: Text(
                  user.displayName ?? 'Unknown User',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Vibe
              if (user.vibe != null && user.vibe!.isNotEmpty)
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mood,
                          size: 18,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          user.vibe!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Proximity
              Center(
                child: Chip(
                  avatar: Icon(
                    Icons.radar,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(
                    '${user.proximity.displayName} (~${user.estimatedDistance.toStringAsFixed(1)}m)',
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Bio
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                Text(
                  'About',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.bio!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Connect button - wrapped with BlocBuilder for real-time updates
              BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                buildWhen: (previous, current) {
                  // Rebuild when connection state changes for this user
                  final prevState = previous.getStateForUser(user.userId ?? '');
                  final currState = current.getStateForUser(user.userId ?? '');
                  return prevState != currState;
                },
                builder: (context, connectionState) {
                  final userConnectionState =
                      connectionState.getStateForUser(user.userId ?? '');
                  final isConnected =
                      userConnectionState == UserConnectionState.connected;
                  final requestSent =
                      userConnectionState == UserConnectionState.requestSent;
                  final requestReceived = userConnectionState ==
                      UserConnectionState.requestReceived;

                  if (isConnected) {
                    // Show message button for connected users
                    return Builder(
                      builder: (builderContext) {
                        // Get current user ID from AuthBloc
                        final authState = builderContext.read<AuthBloc>().state;
                        final currentUserId = authState is AuthAuthenticated
                            ? authState.user.id
                            : '';
                        final otherUserId = user.userId;

                        // Don't show message button if we don't have the user's ID
                        if (otherUserId == null) {
                          return const SizedBox.shrink();
                        }

                        return OutlinedButton.icon(
                          onPressed: () {
                            // Capture navigation data before popping
                            final conversationId =
                                ChatUtils.getDirectMessageChannelId(
                              currentUserId,
                              otherUserId,
                            );
                            final routeExtra = {
                              'currentUserId': currentUserId,
                              'otherUserId': otherUserId,
                              'otherUserName': user.displayName ?? 'Unknown',
                              'otherUserPhotoUrl': user.photoUrl,
                            };
                            final route = Routes.chatWith(conversationId);

                            // Pop first, then navigate using the parent context
                            Navigator.pop(builderContext);

                            // Use a post-frame callback to ensure navigation happens
                            // after the bottom sheet is fully dismissed
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              // Check if the parent navigator context is still valid
                              if (context.mounted) {
                                context.push(route, extra: routeExtra);
                              }
                            });
                          },
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Message'),
                        );
                      },
                    );
                  } else if (requestSent) {
                    // Show pending state
                    return OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.schedule),
                      label: const Text('Request Sent'),
                    );
                  } else if (requestReceived) {
                    // Show accept button
                    return Builder(
                      builder: (builderContext) {
                        return FilledButton.icon(
                          onPressed: () {
                            final request = connectionState
                                .getReceivedRequestFrom(user.userId ?? '');
                            if (request != null) {
                              // Get current user ID from AuthBloc
                              final authState = builderContext.read<AuthBloc>().state;
                              final currentUserId = authState is AuthAuthenticated
                                  ? authState.user.id
                                  : '';
                              final otherUserId = user.userId;

                              if (otherUserId == null) {
                                Navigator.pop(context);
                                return;
                              }

                              // Accept the connection
                              context.read<ConnectionBloc>().add(
                                    ConnectionAcceptRequest(request.id),
                                  );

                              // Prepare navigation data
                              final conversationId =
                                  ChatUtils.getDirectMessageChannelId(
                                currentUserId,
                                otherUserId,
                              );
                              final routeExtra = {
                                'currentUserId': currentUserId,
                                'otherUserId': otherUserId,
                                'otherUserName': user.displayName ?? 'Unknown',
                                'otherUserPhotoUrl': user.photoUrl,
                              };
                              final route = Routes.chatWith(conversationId);

                              // Pop the bottom sheet first
                              Navigator.of(builderContext).pop();

                              // Use a post-frame callback to ensure navigation happens
                              // after the bottom sheet is fully dismissed
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                // Show success snackbar on the main screen
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).clearSnackBars();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Connected with ${user.displayName ?? 'user'}'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );

                                  // Navigate to chat after a brief delay (let the connection be saved)
                                  Future.delayed(const Duration(milliseconds: 500), () {
                                    if (context.mounted) {
                                      context.push(route, extra: routeExtra);
                                    }
                                  });
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Accept Request'),
                        );
                      },
                    );
                  } else {
                    // Show connect button
                    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                      builder: (builderContext, connectionState) {
                        // Get receiver's user ID
                        final receiverId = user.userId;
                        
                        // Check if request is already being processed or sent
                        final isProcessing = receiverId != null &&
                            (connectionState.isActionLoading && 
                             connectionState.processingId == receiverId);
                        
                        final alreadySent = receiverId != null &&
                            (connectionState.getSentRequestTo(receiverId) != null ||
                             connectionState.getStateForUser(receiverId) == UserConnectionState.requestSent);
                        
                        return FilledButton.icon(
                          onPressed: (isProcessing || alreadySent) ? null : () {
                            // Get current user info
                            final authState =
                                builderContext.read<AuthBloc>().state;
                            if (authState is! AuthAuthenticated) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Please sign in to send connection requests'),
                                  duration: Duration(seconds: 3),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }

                            if (receiverId == null) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Cannot connect: User ID not available'),
                                  duration: Duration(seconds: 3),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }

                            // Double-check before sending
                            final currentConnectionState = builderContext.read<ConnectionBloc>().state;
                            if (currentConnectionState.getSentRequestTo(receiverId) != null ||
                                currentConnectionState.getStateForUser(receiverId) == UserConnectionState.requestSent) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Request already sent'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }

                            // Get sender's profile info
                            final profileState =
                                builderContext.read<ProfileBloc>().state;
                            String? senderDisplayName;
                            String? senderPhotoUrl;
                            if (profileState is ProfileLoaded) {
                              senderDisplayName = profileState.profile.name;
                              senderPhotoUrl = profileState.profile.photoUrl;
                            }

                            // Set current user info on the ConnectionBloc
                            builderContext
                                .read<ConnectionBloc>()
                                .setCurrentUser(
                                  userId: authState.user.id,
                                  displayName: senderDisplayName,
                                  photoUrl: senderPhotoUrl,
                                );

                            // Send connection request
                            builderContext
                                .read<ConnectionBloc>()
                                .add(ConnectionSendRequest(
                                  receiverId: receiverId,
                                  source: 'nearby',
                                  receiverDisplayName: user.displayName,
                                  receiverPhotoUrl: user.photoUrl,
                                ));

                            // Show success message (don't close sheet - button will update to "Request Sent")
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Request sent to ${user.displayName ?? 'user'}'),
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: isProcessing 
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.person_add),
                          label: Text(alreadySent ? 'Request Sent' : 'Connect'),
                        );
                      },
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
