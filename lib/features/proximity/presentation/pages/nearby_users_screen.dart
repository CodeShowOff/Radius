import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../domain/entities/nearby_user.dart';
import '../bloc/nearby_users_bloc.dart';
import '../widgets/ble_diagnostics_panel.dart';
import '../widgets/nearby_user_card.dart';
import '../widgets/nearby_users_empty_state.dart';

/// Screen displaying nearby users discovered via BLE.
///
/// - Advertising is started app-wide when user authenticates (to be discoverable)
/// - Scanning starts when user taps "Scan" button (runs for 15 seconds)
/// - Scanning stops when app goes to background
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshBlePermissions());
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

  Future<void> _startScan() async {
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
        'Set Battery saver for Radius to “No restrictions”.',
        'Enable Autostart for Radius (if available).',
        'Lock Radius in Recents (tap the app icon → Lock).',
      ];
    }

    if (key.contains('huawei') || key.contains('honor')) {
      return const [
        'Battery: set Radius to “Not allowed to optimize”.',
        'App launch: manage manually; allow auto-launch + background activity.',
      ];
    }

    if (key.contains('samsung')) {
      return const [
        'Battery: set Radius to “Unrestricted” (or disable “Put unused apps to sleep” for it).',
        'Ensure Bluetooth is allowed while the Nearby screen is open.',
      ];
    }

    if (key.contains('oppo') ||
        key.contains('realme') ||
        key.contains('vivo')) {
      return const [
        'Allow background activity / disable app sleep for Radius.',
        'Battery: set Radius to “Don’t optimize” (or “No restrictions”).',
      ];
    }

    if (key.contains('oneplus')) {
      return const [
        'Battery optimization: set Radius to “Don’t optimize”.',
        'Disable aggressive sleep/hibernation for Radius if available.',
      ];
    }

    return const [
      'Battery optimization: set Radius to “Don’t optimize” / “Unrestricted” if available.',
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
                    'If you see “no nearby users” even when phones are close, this is often caused by permissions, Bluetooth being off, or OEM battery management.',
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
                                      const Text('• '),
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
                          const Text('• Make sure Bluetooth is turned on'),
                          const Text('• Grant all Bluetooth permissions'),
                          const Text(
                              '• Disable battery optimization for this app'),
                          const Text(
                              '• Keep the app in foreground while scanning'),
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
        title: const Text('Nearby'),
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
        listenWhen: (prev, curr) => curr.status == NearbyUsersStatus.error,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
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
              // Header card with scan button
              Container(
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
                                    ? 'Scanning for 15 seconds...'
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

              // Permission banner
              if (_shouldShowPermissionCtaBanner(state))
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

              // Main content
              Expanded(
                child: _buildContent(context, state),
              ),

              // Diagnostics panel at bottom
              const BleDiagnosticsPanel(),
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
        content = _ErrorState(
          message: state.errorMessage ?? 'An error occurred',
          onRetry: _startScan,
        );
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
              color: theme.colorScheme.outline,
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

/// Nearby users list with smooth scrolling.
class _NearbyUsersList extends StatelessWidget {
  final List<NearbyUser> users;
  final bool isDiscovering;

  const _NearbyUsersList({
    required this.users,
    required this.isDiscovering,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
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
        itemCount: users.length + 1, // +1 for footer
        itemExtent: null, // Let items size themselves
        cacheExtent: 200, // Cache items off-screen
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemBuilder: (context, index) {
          if (index == users.length) {
            // Footer with count
            return _ListFooter(
              count: users.length,
              isScanning: isDiscovering,
            );
          }

          final user = users[index];

          // Use RepaintBoundary for smoother scrolling
          // Wrap with BlocBuilder to react to connection state changes
          return RepaintBoundary(
            child: BlocBuilder<ConnectionBloc, ConnectionBlocState>(
              buildWhen: (previous, current) {
                // Rebuild when connection state changes for this user
                final prevState = previous.getStateForUser(user.userId ?? '');
                final currState = current.getStateForUser(user.userId ?? '');
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
          );
        },
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please sign in to send connection requests')),
      );
      return;
    }

    // Get receiver's user ID
    final receiverId = user.userId;
    if (receiverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot connect: User ID not available')),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Connection request sent to ${user.displayName ?? 'user'}'),
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
                                Conversation.createConversationId(
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
                    return FilledButton.icon(
                      onPressed: () {
                        final request = connectionState
                            .getReceivedRequestFrom(user.userId ?? '');
                        if (request != null) {
                          context.read<ConnectionBloc>().add(
                                ConnectionAcceptRequest(request.id),
                              );
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Accepted connection from ${user.displayName ?? 'user'}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Accept Request'),
                    );
                  } else {
                    // Show connect button
                    return Builder(
                      builder: (builderContext) {
                        return FilledButton.icon(
                          onPressed: () {
                            // Get current user info
                            final authState =
                                builderContext.read<AuthBloc>().state;
                            if (authState is! AuthAuthenticated) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Please sign in to send connection requests')),
                              );
                              return;
                            }

                            // Get receiver's user ID
                            final receiverId = user.userId;
                            if (receiverId == null) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Cannot connect: User ID not available')),
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

                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Connection request sent to ${user.displayName ?? 'user'}'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Connect'),
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
