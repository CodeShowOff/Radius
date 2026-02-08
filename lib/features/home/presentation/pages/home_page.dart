import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../../profile/presentation/widgets/mood_selector.dart';

/// Home page - main screen after authentication.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _bluetoothEnabled = false;
  bool _checkingBluetooth = true;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _blinkController.dispose();
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
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Card(
                    elevation: 2,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: const MoodSelector(showLabel: true, compact: false),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick action button - Nearby
                _AnimatedSquareCard(
                  onTap: () => context.push(Routes.nearby),
                  label: 'Nearby',
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  isSquare: true,
                  animationType: _CardAnimationType.wave,
                ),
                const SizedBox(height: 16),

                // Nearby Help section - prominent SOS button
                _AnimatedSquareCard(
                  onTap: () => context.push(Routes.nearbyHelp),
                  label: 'Nearby Help',
                  color: Theme.of(context).colorScheme.error,
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  isSquare: false,
                  useVerticalLayout: false,
                  animationType: _CardAnimationType.sos,
                ),
                const SizedBox(height: 16),

                // Location Based Groups section - Simple card design
                _SimpleGroupCard(
                  onTap: () => context.push(Routes.locationGroups),
                  title: 'Location Based Groups',
                  subtitle: 'Connect with people in your area',
                  icon: Icons.location_on,
                ),
                const SizedBox(height: 16),

                // Discover Groups - Simple card design
                _SimpleGroupCard(
                  onTap: () => context.push(Routes.discoverRandomGroups),
                  title: 'Discover Random Groups',
                  subtitle: 'Join global communities worldwide',
                  icon: Icons.public,
                ),
                const SizedBox(height: 16),
                _SimpleGroupCard(
                  onTap: () => context.push(Routes.discoverNearbyGroups),
                  title: 'Discover Nearby Groups',
                  subtitle: 'Find local communities around you',
                  icon: Icons.all_inclusive,
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

  const _AnimatedSquareCard({
    required this.onTap,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.isSquare = false,
    this.useVerticalLayout = false,
    this.animationType = _CardAnimationType.wave,
  });

  IconData _getIcon() {
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
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(),
                        size: 28,
                        color: color,
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

    final iconBgColor = color.withValues(alpha: 0.2);

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
              color: color,
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

/// Simple card widget for group discovery on home page - consistent with app theme.
class _SimpleGroupCard extends StatelessWidget {
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final IconData icon;

  const _SimpleGroupCard({
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Arrow icon
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
