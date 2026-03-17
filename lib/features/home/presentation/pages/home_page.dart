import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../../core/settings/app_settings_store.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../profile/presentation/widgets/mood_selector.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
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
    final isDark = theme.brightness == Brightness.dark;

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(Routes.login);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Header ---
                Row(
                  children: [
                    Text(
                      'Radius',
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    // Bluetooth warning (only when off)
                    if (!_bluetoothEnabled && !_checkingBluetooth)
                      _buildBluetoothIcon(),
                    // Notification bell
                    IconButton(
                      onPressed: () => context.push(Routes.notificationSettings),
                      icon: Icon(
                        Icons.notifications_outlined,
                        size: 24,
                        color: isDark ? Colors.white70 : AppTheme.primaryColor,
                      ),
                      tooltip: 'Notifications',
                    ),
                    // Connection requests with badge
                    BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                      buildWhen: (prev, curr) =>
                          prev.receivedRequests.length !=
                          curr.receivedRequests.length,
                      builder: (context, state) {
                        final count = state.receivedRequests.length;
                        return IconButton(
                          onPressed: () => context.push(Routes.allRequests),
                          icon: Badge(
                            isLabelVisible: count > 0,
                            backgroundColor: Colors.red,
                            label: count > 0
                                ? Text('$count',
                                    style: const TextStyle(fontSize: 10))
                                : null,
                            child: Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 24,
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.primaryColor,
                            ),
                          ),
                          tooltip: 'Requests',
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Discover people around you',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // --- Mood Card ---
                _buildMoodCard(context, theme, isDark),
                const SizedBox(height: 12),

                // --- Background Advertising Card ---
                _buildBgAdvCard(context, theme, isDark),
                const SizedBox(height: 20),

                // --- Find People Hero Card ---
                _buildHeroCard(context, theme),
                const SizedBox(height: 28),

                // --- Quick Connect ---
                Text(
                  'Quick Connect',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickConnectCard(
                        icon: Icons.chat_bubble_rounded,
                        label: 'Random',
                        subtitle: 'Chat',
                        color: AppTheme.primaryColor,
                        onTap: () => context.push(Routes.randomChat),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickConnectCard(
                        icon: Icons.person_search_rounded,
                        label: 'Find',
                        subtitle: 'People',
                        color: AppTheme.primaryColor,
                        onTap: () => context.push(Routes.discoverySearch),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // --- Groups Around You ---
                Text(
                  'Groups Around You',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _GroupCard(
                        icon: Icons.all_inclusive,
                        label: 'Nearby',
                        subtitle: 'Groups',
                        color: const Color(0xFFE91E63),
                        onTap: () => context.push(Routes.nearbyGroups),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GroupCard(
                        icon: Icons.location_on,
                        label: 'Location',
                        subtitle: 'Groups',
                        color: const Color(0xFF2196F3),
                        onTap: () => context.push(Routes.myGroups),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GroupCard(
                        icon: Icons.casino_rounded,
                        label: 'Random',
                        subtitle: 'Groups',
                        color: AppTheme.primaryColor,
                        onTap: () => context.push(Routes.randomGroups),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // --- Emergency Help ---
                _EmergencyHelpCard(
                  onTap: () => context.push(Routes.nearbyHelp),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Mood Card ---
  Widget _buildMoodCard(
      BuildContext context, ThemeData theme, bool isDark) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        String moodLabel = 'Set Mood';
        IconData moodIcon = Icons.mood_outlined;

        if (profileState is ProfileLoaded &&
            profileState.profile.mood != null) {
          final mood = profileState.profile.mood!;
          // Support both old emoji keys ('😊 Chill') and new clean values ('Chill')
          final cleanMood = MoodSelector.moods[mood] ?? mood;
          moodLabel = '$cleanMood Mood';
          const moodIcons = {
            'Chill': Icons.sentiment_satisfied_alt,
            'Focused': Icons.psychology,
            'Deep talk': Icons.forum,
            'Fun': Icons.celebration,
          };
          moodIcon = moodIcons[cleanMood] ?? Icons.mood;
        }

        return GestureDetector(
          onTap: () => _showMoodPicker(context),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.primaryColor.withValues(alpha: 0.3)
                        : AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(moodIcon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    moodLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_circle_outlined,
                  color: theme.colorScheme.secondary,
                  size: 22,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Background Advertising Card ---
  Widget _buildBgAdvCard(
      BuildContext context, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _backgroundAdvertising
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.broadcast_on_personal,
            size: 20,
            color: _backgroundAdvertising
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _backgroundAdvertising
                  ? AppTheme.successColor
                  : theme.colorScheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _backgroundAdvertising ? 'Visible' : 'Hidden',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _backgroundAdvertising
                  ? AppTheme.successColor
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _backgroundAdvertising
                  ? 'Discoverable in background'
                  : 'Hidden when app closed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: FittedBox(
              child: Switch(
                value: _backgroundAdvertising,
                onChanged: _toggleBackgroundAdvertising,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Hero Find People Card ---
  Widget _buildHeroCard(BuildContext context, ThemeData theme) {
    return GestureDetector(
      onTap: () => context.push(Routes.nearby),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF3D1566),
              Color(0xFF7B2EA8),
              Color(0xFFB44088),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -10,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            Positioned(
              left: -15,
              bottom: -15,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),
            // Content
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find People\nNear You',
                        style:
                            theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'See who is around you\nright now',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFE040A0),
                              Color(0xFF8B2FC9),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE040A0)
                                  .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Start Exploring',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Magnifying glass illustration
                SizedBox(
                  width: 100,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer glow ring
                      Container(
                        width: 85,
                        height: 85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                Colors.white.withValues(alpha: 0.12),
                            width: 2,
                          ),
                        ),
                      ),
                      // Inner circle with icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                Colors.white.withValues(alpha: 0.2),
                            width: 2,
                          ),
                          color:
                              Colors.white.withValues(alpha: 0.08),
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          color:
                              Colors.white.withValues(alpha: 0.9),
                          size: 30,
                        ),
                      ),
                      // Decorative dots
                      Positioned(
                        right: 5,
                        top: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        bottom: 15,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 15,
                        bottom: 8,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Mood picker bottom sheet ---
  void _showMoodPicker(BuildContext context) {
    const moodIcons = {
      'Chill': Icons.sentiment_satisfied_alt,
      'Focused': Icons.psychology,
      'Deep talk': Icons.forum,
      'Fun': Icons.celebration,
    };

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final sheetTheme = Theme.of(ctx);
        final profileState = context.read<ProfileBloc>().state;
        final rawMood =
            profileState is ProfileLoaded ? profileState.profile.mood : null;
        // Normalise stored mood to clean value for comparison
        final currentMood =
            rawMood != null ? (MoodSelector.moods[rawMood] ?? rawMood) : null;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Set Your Mood',
                  style: sheetTheme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...MoodSelector.moods.entries.map((entry) {
                final isSelected = currentMood == entry.value;
                return ListTile(
                  leading: Icon(
                    moodIcons[entry.value] ?? Icons.mood,
                    color: isSelected
                        ? sheetTheme.colorScheme.primary
                        : sheetTheme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(entry.value),
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: sheetTheme.colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateMood(context, entry.value);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _updateMood(BuildContext context, String mood) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) return;
    final updatedProfile = profileState.profile.copyWith(
      mood: mood,
      updatedAt: DateTime.now(),
    );
    context.read<ProfileBloc>().add(ProfileUpdateRequested(updatedProfile));
  }
}

// --- Quick Connect Card ---
class _QuickConnectCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickConnectCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- Group Card ---
class _GroupCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GroupCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Emergency Help Card ---
class _EmergencyHelpCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EmergencyHelpCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final errorColor = theme.colorScheme.error;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: errorColor.withValues(alpha: isDark ? 0.1 : 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: errorColor.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            // SOS badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: errorColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emergency Help',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Instantly alert nearby users',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // SOS Button
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: errorColor,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'SOS',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


