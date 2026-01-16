import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/services/bluetooth/bluetooth_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/connections/presentation/bloc/connection_bloc.dart';

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
        ],
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
    );
  }
}
