import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';

/// Home page - main screen after authentication.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _bluetoothEnabled = false;
  bool _checkingBluetooth = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBluetoothStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check Bluetooth when app comes back to foreground
      _checkBluetoothStatus();
    }
  }

  Future<void> _checkBluetoothStatus() async {
    setState(() => _checkingBluetooth = true);
    try {
      final bluetoothService = context.read<BluetoothService>();
      final isEnabled = await bluetoothService.isBluetoothEnabled();
      if (mounted) {
        setState(() {
          _bluetoothEnabled = isEnabled;
          _checkingBluetooth = false;
        });
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
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(Routes.login);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Radius'),
          actions: [
            BlocBuilder<ProfileBloc, ProfileState>(
              builder: (context, profileState) {
                return BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, authState) {
                    String? photoUrl;
                    String displayName = 'U';

                    if (authState is AuthAuthenticated) {
                      photoUrl = authState.user.avatarUrl;
                      displayName = authState.user.displayName ?? 'U';
                    }

                    if (profileState is ProfileLoaded) {
                      if (profileState.profile.photoUrl != null &&
                          profileState.profile.photoUrl!.isNotEmpty) {
                        photoUrl = profileState.profile.photoUrl;
                      }
                      if (profileState.profile.name.isNotEmpty) {
                        displayName = profileState.profile.name;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        onPressed: () => context.push(Routes.profile),
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage:
                              photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome card - now uses ProfileBloc for name
                BlocBuilder<ProfileBloc, ProfileState>(
                  builder: (context, profileState) {
                    return BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, authState) {
                        String userName = 'there';
                        if (authState is AuthAuthenticated) {
                          // Prefer profile name over auth displayName
                          if (profileState is ProfileLoaded &&
                              profileState.profile.name.isNotEmpty) {
                            userName = profileState.profile.name;
                          } else {
                            userName = authState.user.displayName ?? 'there';
                          }
                        }
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hello, $userName! 👋',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Ready to discover people nearby?',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Status card
                _BluetoothStatusCard(
                  isEnabled: _bluetoothEnabled,
                  isChecking: _checkingBluetooth,
                  onRefresh: _checkBluetoothStatus,
                  onEnableTap: _requestBluetoothOn,
                ),
                const SizedBox(height: 16),

                // Quick action buttons row
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.push(Routes.nearby),
                        icon: const Icon(Icons.radar),
                        label: const Text('Nearby'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => context.push(Routes.connections),
                        icon: const Icon(Icons.people),
                        label: const Text('Connections'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Connections section header with "View All" button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Connections',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.connections),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No connections yet',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start scanning to find people nearby',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bluetooth status card widget showing current state.
class _BluetoothStatusCard extends StatelessWidget {
  final bool isEnabled;
  final bool isChecking;
  final VoidCallback onRefresh;
  final VoidCallback onEnableTap;

  const _BluetoothStatusCard({
    required this.isEnabled,
    required this.isChecking,
    required this.onRefresh,
    required this.onEnableTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusText = isChecking
        ? 'Checking...'
        : isEnabled
            ? 'Ready'
            : 'Off';

    final statusColor = isChecking
        ? theme.colorScheme.surfaceContainerHighest
        : isEnabled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer;

    final statusTextColor = isChecking
        ? theme.colorScheme.onSurface
        : isEnabled
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onErrorContainer;

    final iconColor = isChecking
        ? theme.colorScheme.outline
        : isEnabled
            ? theme.colorScheme.primary
            : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled ? Icons.bluetooth : Icons.bluetooth_disabled,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Bluetooth Status',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (isChecking)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: onRefresh,
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                  ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!isEnabled && !isChecking) ...[
              Text(
                'Please turn on Bluetooth to discover nearby users',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onEnableTap,
                icon: const Icon(Icons.bluetooth),
                label: const Text('Turn On Bluetooth'),
              ),
            ] else
              const Text('Tap below to start scanning for nearby users'),
          ],
        ),
      ),
    );
  }
}
