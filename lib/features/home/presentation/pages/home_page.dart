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
            // Bluetooth status icon
            IconButton(
              onPressed: () {
                if (!_bluetoothEnabled && !_checkingBluetooth) {
                  _showBluetoothPrompt(context);
                }
              },
              icon: Icon(
                _bluetoothEnabled ? Icons.bluetooth : Icons.bluetooth_disabled,
                color: _checkingBluetooth
                    ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                    : _bluetoothEnabled
                        ? Colors.blue
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                size: 22,
              ),
              tooltip: _checkingBluetooth
                  ? 'Checking Bluetooth...'
                  : _bluetoothEnabled
                      ? 'Bluetooth is on'
                      : 'Bluetooth is off - Tap to enable',
            ),
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
                // Mood selector with gradient
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF667eea),
                        const Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const MoodSelector(showLabel: true, compact: false),
                ),
                const SizedBox(height: 16),

                // Quick action buttons row - Nearby and Guess Me
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.nearby),
                        label: 'Nearby',
                        color: Colors.white,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        gradientColors: [
                          const Color(0xFF667eea),
                          const Color(0xFF764ba2),
                        ],
                        isSquare: true,
                        animationType: _CardAnimationType.wave,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.guessme),
                        label: 'Guess Me',
                        color: Colors.white,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        gradientColors: [
                          const Color(0xFF667eea),
                          const Color(0xFF764ba2),
                        ],
                        isSquare: true,
                        animationType: _CardAnimationType.personCycle,
                      ),
                    ),
                  ],
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

                // Location Based Groups section - Modern gradient design
                _ModernGroupCard(
                  onTap: () => context.push(Routes.locationGroups),
                  title: 'Location Based Groups',
                  subtitle: 'Connect with people in your area',
                  icon: Icons.location_on,
                  gradientColors: [
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                  ],
                ),
                const SizedBox(height: 16),

                // Discover Groups - Modern gradient design
                _ModernGroupCard(
                  onTap: () => context.push(Routes.discoverRandomGroups),
                  title: 'Discover Random Groups',
                  subtitle: 'Join global communities worldwide',
                  icon: Icons.public,
                  gradientColors: [
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                  ],
                ),
                const SizedBox(height: 16),
                _ModernGroupCard(
                  onTap: () => context.push(Routes.discoverNearbyGroups),
                  title: 'Discover Nearby Groups',
                  subtitle: 'Find local communities around you',
                  icon: Icons.bluetooth_searching,
                  gradientColors: [
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
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
  final List<Color>? gradientColors;
  final bool isSquare;
  final bool useVerticalLayout;
  final _CardAnimationType animationType;

  const _AnimatedSquareCard({
    required this.onTap,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.gradientColors,
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

    if (gradientColors != null) {
      // Use gradient style
      return GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors!,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradientColors![0].withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: (isSquare || useVerticalLayout)
              ? _buildVerticalContent(theme)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
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

    // Use solid color style
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: backgroundColor,
        child: (isSquare || useVerticalLayout)
            ? _buildVerticalContent(theme)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    
    // Use white with transparency for gradient backgrounds
    final iconBgColor = gradientColors != null 
        ? Colors.white.withValues(alpha: 0.2)
        : color.withValues(alpha: 0.2);

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

/// Modern card widget with gradient background for group discovery on home page.
class _ModernGroupCard extends StatelessWidget {
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;

  const _ModernGroupCard({
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradientColors[0].withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon container with white background
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Colors.white,
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
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
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
                size: 18,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

