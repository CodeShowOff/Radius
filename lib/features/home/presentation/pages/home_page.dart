import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../../core/settings/app_settings_store.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../profile/presentation/widgets/mood_selector.dart';
import '../../../proximity/proximity_service.dart';

/// Home page - main screen after authentication.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin, RouteAware {
  bool _bluetoothEnabled = false;
  bool _checkingBluetooth = true;
  bool _backgroundAdvertising = false;

  final _proximityService = getIt<ProximityService>();
  final _settingsStore = getIt<AppSettingsStore>();

  // Animation controller for Bluetooth off state (simple blinking)
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize blink animation (for icon opacity pulsing)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _blinkAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _checkBluetoothStatus();
    _checkBackgroundAdvertising();
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
    _blinkController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check Bluetooth and Background Advertising when app comes back to foreground
      _checkBluetoothStatus();
      _checkBackgroundAdvertising();
    }
  }

  @override
  void didPopNext() {
    // Called when returning to this route from another route
    // Re-check background advertising setting to sync with Bluetooth Settings page
    _checkBackgroundAdvertising();
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
        _updateBluetoothAnimations();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bluetoothEnabled = false;
          _checkingBluetooth = false;
        });
        _updateBluetoothAnimations();
      }
    }
  }

  void _updateBluetoothAnimations() {
    if (!_bluetoothEnabled && !_checkingBluetooth) {
      // Start blinking animation when Bluetooth is off
      _blinkController.repeat(reverse: true);
    } else {
      // Stop animation when Bluetooth is on or checking
      _blinkController.stop();
      _blinkController.reset();
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

  void _checkBackgroundAdvertising() {
    final bgAdv = _settingsStore.getBackgroundAdvertising();
    setState(() {
      _backgroundAdvertising = bgAdv;
    });
  }

  Future<void> _toggleBackgroundAdvertising(bool value) async {
    // If turning OFF, show confirmation dialog
    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disable Background Advertising?'),
          content: const Text(
            'Nearby users won\'t be able to discover you when the app is closed. '
            'Battery usage is minimal (less than 1% per day).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Disable'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return; // User cancelled
      }
    }

    // Update state
    setState(() => _backgroundAdvertising = value);
    await _proximityService.setBackgroundAdvertising(value);
  }

  void _showBluetoothPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth is Off'),
        content: const Text(
          'Please turn on Bluetooth to discover nearby users and use all features of Radius.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _requestBluetoothOn();
            },
            icon: const Icon(Icons.bluetooth),
            label: const Text('Turn On'),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothIcon() {
    if (_checkingBluetooth) {
      // Show loading state
      return IconButton(
        onPressed: null,
        icon: Icon(
          Icons.bluetooth,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          size: 26,
        ),
        tooltip: 'Checking Bluetooth...',
      );
    }

    if (_bluetoothEnabled) {
      // Bluetooth is on - show normal blue icon (more bold)
      return IconButton(
        onPressed: null,
        icon: const Icon(
          Icons.bluetooth,
          color: Colors.blue,
          size: 26,
          weight: 700,
        ),
        tooltip: 'Bluetooth is on',
      );
    }

    // Bluetooth is off - show blinking red icon (no waves)
    return GestureDetector(
      onTap: () => _showBluetoothPrompt(context),
      child: Tooltip(
        message: 'Bluetooth is off - Tap to enable',
        child: IconButton(
          onPressed: null,
          icon: AnimatedBuilder(
            animation: _blinkAnimation,
            builder: (context, child) {
              return Icon(
                Icons.bluetooth_disabled,
                color: Colors.red.withValues(alpha: _blinkAnimation.value),
                size: 26,
                weight: 700,
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(Routes.login);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Radius',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          actions: [
            _buildBluetoothIcon(),
            BlocBuilder<ConnectionBloc, ConnectionBlocState>(
              buildWhen: (prev, curr) =>
                  prev.receivedRequests.length != curr.receivedRequests.length,
              builder: (context, state) {
                final hasRequests = state.receivedRequests.isNotEmpty;
                return IconButton(
                  onPressed: () => context.push(Routes.allRequests),
                  icon: Badge(
                    isLabelVisible: hasRequests,
                    backgroundColor: Colors.red,
                    smallSize: 10,
                    child: const Icon(Icons.person_add_alt_1_outlined, size: 24),
                  ),
                  tooltip: 'Requests',
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final bottomPad = 16.0 + MediaQuery.of(context).padding.bottom;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 12 - bottomPad,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Mood + Status row ---
                      const MoodSelector(showLabel: true, compact: false),
                      const SizedBox(height: 12),

                      // --- Background Advertising compact toggle ---
                      _BackgroundAdvToggle(
                        enabled: _backgroundAdvertising,
                        onChanged: _toggleBackgroundAdvertising,
                      ),
                      const SizedBox(height: 28),

                      // --- Quick Actions ---
                      Text(
                        'Quick Actions',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.radar,
                              label: 'Find Nearby',
                              onTap: () => context.push(Routes.nearby),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.shuffle,
                              label: 'Random Chat',
                              onTap: () => context.push(Routes.randomChat),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.videocam_rounded,
                              label: 'Video Chat',
                              onTap: () => context.push(Routes.videoChat),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _QuickAction(
                              icon: Icons.sos,
                              label: 'Nearby Help',
                              onTap: () => context.push(Routes.nearbyHelp),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),

                      // --- Groups section ---
                      Text(
                        'Groups',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _FeatureCard(
                              icon: Icons.location_on_outlined,
                              label: 'Location\nGroups',
                              onTap: () => context.push(Routes.myGroups),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FeatureCard(
                              icon: Icons.public_outlined,
                              label: 'Random\nGroups',
                              onTap: () => context.push(Routes.randomGroups),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FeatureCard(
                              icon: Icons.all_inclusive,
                              label: 'Nearby\nGroups',
                              onTap: () => context.push(Routes.nearbyGroups),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// --- Reusable widgets ---

/// Compact background advertising toggle.
class _BackgroundAdvToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _BackgroundAdvToggle({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.broadcast_on_personal,
            size: 20,
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              enabled ? 'Discoverable in background' : 'Hidden when app closed',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                value: enabled,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width quick-action card with icon and label.
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 36),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact feature card for groups grid.
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
