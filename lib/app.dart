import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/services/bluetooth/bluetooth_service.dart';
import 'core/services/bluetooth/ble_range_mode.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/connections/presentation/bloc/connection_bloc.dart';
import 'features/proximity/proximity_service.dart';
import 'features/profile/presentation/bloc/profile_bloc.dart';

/// Root widget of the Radius application.
///
/// Configures global providers, theme, and routing.
class RadiusApp extends StatelessWidget {
  const RadiusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        // Provide BluetoothService for Bluetooth status checking
        RepositoryProvider<BluetoothService>.value(
          value: getIt<BluetoothService>(),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          // Global BLoCs that need to be available app-wide
          BlocProvider<AuthBloc>(
            create: (_) => getIt<AuthBloc>(),
          ),
          // Connection BLoC for managing user connections app-wide
          BlocProvider<ConnectionBloc>(
            create: (_) => getIt<ConnectionBloc>(),
          ),
          // Profile BLoC for managing user profile app-wide
          BlocProvider<ProfileBloc>(
            create: (_) => getIt<ProfileBloc>(),
          ),
        ],
        child: _BlePresenceManager(
          child: MaterialApp.router(
            title: 'Radius',
            debugShowCheckedModeBanner: false,

            // Theme configuration
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,

            // Router configuration
            routerConfig: appRouter,
          ),
        ),
      ),
    );
  }
}

/// Manages foreground BLE presence.
///
/// Requirements:
/// - Advertise the device ID while the app is being used (foreground).
/// - Do NOT scan in the background or app-wide; scanning only happens on Nearby.
class _BlePresenceManager extends StatefulWidget {
  final Widget child;

  const _BlePresenceManager({required this.child});

  @override
  State<_BlePresenceManager> createState() => _BlePresenceManagerState();
}

class _BlePresenceManagerState extends State<_BlePresenceManager>
    with WidgetsBindingObserver {
  final BluetoothService _bluetoothService = getIt<BluetoothService>();
  final ProximityService _proximityService = getIt<ProximityService>();

  String? _currentUserId;
  bool _isForeground = true;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // If the app starts already authenticated, BlocListener won't fire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onAuthChanged(context, context.read<AuthBloc>().state);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort stop (don't await in dispose).
    _bluetoothService.stopAdvertising();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _bluetoothService.onAppForegroundChanged(true);
      _ensureForegroundPresence();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _isForeground = false;
      _bluetoothService.onAppForegroundChanged(false);
      _bluetoothService.stopAdvertising();
    }
  }

  Future<void> _ensureForegroundPresence() async {
    if (!_isForeground) return;
    final userId = _currentUserId;
    if (userId == null) return;
    if (_starting) return;
    _starting = true;

    try {
      // Initialize ProximityService so it can keep Firestore bleIdentifier in-sync
      // with BluetoothService's rotating anonymous ID.
      await _proximityService.initialize(userId);

      // Advertising is the only always-on behavior; scanning is user-triggered.
      await _bluetoothService.startAdvertising(rangeMode: BleRangeMode.large);
    } finally {
      _starting = false;
    }
  }

  void _onAuthChanged(BuildContext context, AuthState state) {
    if (state is AuthAuthenticated) {
      final newUserId = state.user.id;
      final userChanged = _currentUserId != newUserId;
      _currentUserId = newUserId;

      // Make sure profile data (including display name) starts loading as soon
      // as the user is authenticated, so HomePage can render the correct name
      // without requiring navigation to Profile first.
      if (userChanged) {
        try {
          context.read<ProfileBloc>().add(ProfileLoadRequested(newUserId));
        } catch (_) {
          // Ignore if ProfileBloc isn't available in the tree yet.
        }
      }

      _ensureForegroundPresence();
      return;
    }

    // Signed out or unauthenticated.
    _currentUserId = null;
    _bluetoothService.stopAdvertising();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: _onAuthChanged,
      child: widget.child,
    );
  }
}
