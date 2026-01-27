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
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mood selector
                const MoodSelector(showLabel: true, compact: false),
                const SizedBox(height: 16),

                // Quick action buttons row - Nearby and Guess Me
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.nearby),
                        label: 'Nearby',
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        isSquare: true,
                        animationType: _CardAnimationType.wave,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.guessme),
                        label: 'Guess Me',
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        isSquare: true,
                        animationType: _CardAnimationType.personCycle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Location Based Groups section - same height as square cards
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate height to match square cards
                    // Width of each square card = (total width - gap) / 2
                    final squareCardWidth = (constraints.maxWidth - 12) / 2;
                    return SizedBox(
                      height: squareCardWidth,
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.locationGroups),
                        label: 'Location Based Groups',
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        isSquare: false,
                        useVerticalLayout: true,
                        animationType: _CardAnimationType.talking,
                      ),
                    );
                  },
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
    final bool compact = !isSquare;
    final EdgeInsets outerPadding =
        compact ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) : const EdgeInsets.all(18);
    final double iconPad = compact ? 12 : 14;
    final double iconSize = compact ? 28 : 34;
    final double gap = compact ? 8 : 12;

    final content = Padding(
      padding: outerPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(iconPad),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
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
            style: (compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleLarge)
                ?.copyWith(
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

enum _CardAnimationType { wave, personCycle, talking }

