import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/services/bluetooth/bluetooth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/connections/presentation/bloc/connection_bloc.dart';
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
        child: _AuthAwareApp(
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

/// Listens to auth state and triggers profile loading on authentication.
///
/// BLE discovery is now fully managed by the Nearby Users screen,
/// not at the app-wide level.
class _AuthAwareApp extends StatefulWidget {
  final Widget child;

  const _AuthAwareApp({required this.child});

  @override
  State<_AuthAwareApp> createState() => _AuthAwareAppState();
}

class _AuthAwareAppState extends State<_AuthAwareApp> {
  String? _currentUserId;

  @override
  void initState() {
    super.initState();

    // If the app starts already authenticated, BlocListener won't fire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onAuthChanged(context, context.read<AuthBloc>().state);
    });
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
      return;
    }

    // Signed out or unauthenticated.
    _currentUserId = null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: _onAuthChanged,
      child: widget.child,
    );
  }
}
