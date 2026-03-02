import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../../core/settings/app_settings_store.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../connections/presentation/bloc/discovery_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
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
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            // Bluetooth status icon with animation when off
            _buildBluetoothIcon(),
            BlocBuilder<ProfileBloc, ProfileState>(
              builder: (context, profileState) {
                return BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, authState) {
                    String? photoUrl;
                    String displayName = 'U';

                    // Use profile data as primary source (same logic as connections page)
                    if (profileState is ProfileLoaded) {
                      photoUrl = profileState.profile.photoUrl;
                      displayName = profileState.profile.name.isNotEmpty
                          ? profileState.profile.name
                          : 'U';
                    } else if (authState is AuthAuthenticated) {
                      // Fallback to auth data only if profile not loaded
                      photoUrl = authState.user.avatarUrl;
                      displayName = authState.user.displayName ?? 'U';
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        onPressed: () => context.push(Routes.profile),
                        icon: CachedAvatar(
                          imageUrl: photoUrl,
                          name: displayName,
                          radius: 16,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push(Routes.discoverySearch),
          heroTag: 'searchUsers',
          tooltip: 'Find People',
          child: const Icon(Icons.person_search),
        ),
        body: SafeArea(
          bottom: true,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mood selector - with blue border effect
                const MoodSelector(showLabel: true, compact: false),
                const SizedBox(height: 16),

                // Background Advertising Toggle Card
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.broadcast_on_personal,
                          color: _backgroundAdvertising
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          size: 28,
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
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _backgroundAdvertising
                                    ? 'Discoverable when app closed'
                                    : 'Hidden when app closed',
                                style: TextStyle(
                                  fontSize: 13,
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
                          onChanged: (value) =>
                              _toggleBackgroundAdvertising(value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick action buttons - Nearby & Random Chat
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.nearby),
                        label: 'Find\nNearby',
                        color: Theme.of(context).colorScheme.onPrimary,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        isSquare: true,
                        animationType: _CardAnimationType.wave,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.randomChat),
                        label: 'Random\nChat',
                        color: Theme.of(context).colorScheme.onPrimary,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        isSquare: true,
                        animationType: _CardAnimationType.personCycle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Received request buttons row
                Row(
                  children: [
                    Expanded(
                      child: _RequestButtonCard(
                        onTap: () => context.push(Routes.connectionRequests),
                        label: 'Nearby\nRequest',
                        icon: Icons.mail_outline,
                        badgeBuilder: (context) {
                          return BlocBuilder<ConnectionBloc,
                              ConnectionBlocState>(
                            buildWhen: (prev, curr) {
                              final prevCount = prev.receivedRequests
                                  .where((req) => req.source == 'nearby')
                                  .length;
                              final currCount = curr.receivedRequests
                                  .where((req) => req.source == 'nearby')
                                  .length;
                              return prevCount != currCount;
                            },
                            builder: (context, state) {
                              final count = state.receivedRequests
                                  .where((req) => req.source == 'nearby')
                                  .length;
                              if (count == 0) return const SizedBox.shrink();
                              return _BadgeCount(
                                count: count,
                                color:
                                    Theme.of(context).colorScheme.error,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RequestButtonCard(
                        onTap: () => context.push(Routes.discoveryRequests),
                        label: 'Connection\nRequest',
                        icon: Icons.person_search_outlined,
                        badgeBuilder: (context) {
                          return BlocBuilder<DiscoveryBloc, DiscoveryState>(
                            buildWhen: (prev, curr) =>
                                prev.receivedRequests.length !=
                                curr.receivedRequests.length,
                            builder: (context, state) {
                              final count = state.receivedRequests.length;
                              if (count == 0) return const SizedBox.shrink();
                              return _BadgeCount(
                                count: count,
                                color:
                                    Theme.of(context).colorScheme.tertiary,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Nearby Help section - prominent SOS button
                _AnimatedSquareCard(
                  onTap: () => context.push(Routes.nearbyHelp),
                  label: 'Nearby Help',
                  color: Theme.of(context).colorScheme.onError,
                  backgroundColor: Theme.of(context).colorScheme.error,
                  isSquare: false,
                  useVerticalLayout: false,
                  animationType: _CardAnimationType.sos,
                ),
                const SizedBox(height: 16),

                // Groups section - Square cards in rows
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.videoChat),
                        label: 'Video\nChat',
                        color: Theme.of(context).colorScheme.onTertiary,
                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                        isSquare: true,
                        icon: Icons.videocam_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.locationGroups),
                        label: 'Location\nGroups',
                        color: Theme.of(context).colorScheme.onPrimary,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        isSquare: true,
                        icon: Icons.location_on,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.discoverRandomGroups),
                        label: 'Random\nGroups',
                        color: Theme.of(context).colorScheme.onPrimary,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        isSquare: true,
                        icon: Icons.public,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.discoverNearbyGroups),
                        label: 'Nearby\nGroups',
                        color: Theme.of(context).colorScheme.onPrimary,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        isSquare: true,
                        icon: Icons.all_inclusive,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple card widget for home page action buttons.
class _AnimatedSquareCard extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final Color color;
  final Color backgroundColor;
  final bool isSquare;
  final bool useVerticalLayout;
  final _CardAnimationType animationType;
  final IconData? icon;

  const _AnimatedSquareCard({
    required this.onTap,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.isSquare = false,
    this.useVerticalLayout = false,
    this.animationType = _CardAnimationType.wave,
    this.icon,
  });

  IconData _getIcon() {
    if (icon != null) return icon!;
    switch (animationType) {
      case _CardAnimationType.wave:
        return Icons.radar;
      case _CardAnimationType.personCycle:
        return Icons.psychology;
      case _CardAnimationType.talking:
        return Icons.groups;
      case _CardAnimationType.sos:
        return Icons.sos;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use solid color style
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: backgroundColor,
        child: (isSquare || useVerticalLayout)
            ? _buildVerticalContent(theme)
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: animationType == _CardAnimationType.sos
                            ? theme.colorScheme.onError
                            : theme.colorScheme.onPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(),
                        size: 28,
                        color: animationType == _CardAnimationType.sos
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildVerticalContent(ThemeData theme) {
    // Use same size for all cards
    final EdgeInsets outerPadding = const EdgeInsets.all(18);
    final double iconPad = 14;
    final double iconSize = 34;
    final double gap = 12;

    // Use error colors for SOS, contrasting colors for others
    // Icon circle should contrast with card background
    final bool isSos = animationType == _CardAnimationType.sos;
    final iconBgColor = isSos ? theme.colorScheme.onError : theme.colorScheme.onPrimary;
    final iconColor = isSos ? theme.colorScheme.error : theme.colorScheme.primary;

    final content = Padding(
      padding: outerPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(iconPad),
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getIcon(),
              size: iconSize,
              color: iconColor,
            ),
          ),
          SizedBox(height: gap),
          Text(
            label,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (isSquare) {
      return AspectRatio(
        aspectRatio: 1,
        child: content,
      );
    }

    return Center(child: content);
  }
}

enum _CardAnimationType { wave, personCycle, talking, sos }

/// Card button for received connection/discovery requests on home page.
class _RequestButtonCard extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Widget Function(BuildContext context) badgeBuilder;

  const _RequestButtonCard({
    required this.onTap,
    required this.label,
    required this.icon,
    required this.badgeBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 28,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  Positioned(
                    right: -4,
                    top: -4,
                    child: badgeBuilder(context),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Badge count indicator for request buttons.
class _BadgeCount extends StatelessWidget {
  final int count;
  final Color color;

  const _BadgeCount({
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      constraints: const BoxConstraints(
        minWidth: 20,
        minHeight: 20,
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
