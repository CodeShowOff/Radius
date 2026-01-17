import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/email_verification_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/chat/presentation/bloc/chat_bloc.dart';
import '../../features/chat/presentation/bloc/conversations_bloc.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/conversations_screen.dart';
import '../../features/connections/presentation/pages/connection_requests_screen.dart';
import '../../features/connections/presentation/pages/connections_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/bluetooth_settings_page.dart';
import '../diagnostics/presentation/pages/diagnostics_logs_page.dart';
import '../../features/profile/presentation/pages/privacy_settings_page.dart';
import '../../features/profile/presentation/pages/help_support_page.dart';
import '../../features/proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../features/proximity/presentation/pages/nearby_users_screen.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../config/app_config.dart';
import '../di/injection.dart';
import '../services/analytics/analytics_service.dart';
import 'routes.dart';

/// Routes that don't require authentication.
const _publicRoutes = {
  Routes.splash,
  Routes.login,
  Routes.register,
  Routes.emailVerification,
};

GoRouter? _router;

List<NavigatorObserver> _buildObservers() {
  if (!AppConfig.enableAnalytics) return const [];
  try {
    return [getIt<AnalyticsService>().observer];
  } catch (_) {
    // DI may not be ready in unusual initialization scenarios.
    // Prefer a working app without analytics over a startup crash.
    return const [];
  }
}

/// Application router configuration using GoRouter.
///
/// Defines all navigation routes and their corresponding pages.
/// Includes authentication redirect logic to protect routes.
GoRouter get appRouter {
  return _router ??= GoRouter(
    initialLocation: Routes.splash,
    debugLogDiagnostics: AppConfig.enableDebugLogging,
    observers: _buildObservers(),
    redirect: (BuildContext context, GoRouterState state) {
      // Get the current auth state from the bloc
      final authBloc = context.read<AuthBloc>();
      final authState = authBloc.state;

      final currentPath = state.matchedLocation;
      final isPublicRoute = _publicRoutes.contains(currentPath);

      // During initial load or auth check, don't redirect
      if (authState is AuthInitial || authState is AuthLoading) {
        // Only allow splash page during initial state
        if (currentPath != Routes.splash) {
          return Routes.splash;
        }
        return null;
      }

      final isAuthenticated = authState is AuthAuthenticated;

      // If user is not authenticated and trying to access protected route
      if (!isAuthenticated && !isPublicRoute) {
        // Redirect to login
        return Routes.login;
      }

      // If user is authenticated and trying to access auth routes (login/register)
      if (isAuthenticated &&
          (currentPath == Routes.login || currentPath == Routes.register)) {
        // Redirect to home
        return Routes.home;
      }

      // If user is awaiting email verification
      if (authState is AuthAwaitingEmailVerification) {
        if (currentPath != Routes.emailVerification) {
          return Routes.emailVerification;
        }
        return null;
      }

      // If user is authenticated and on splash, redirect to home
      if (isAuthenticated && currentPath == Routes.splash) {
        return Routes.home;
      }

      // If user is not authenticated and on splash (after auth check), go to login
      if (!isAuthenticated &&
          currentPath == Routes.splash &&
          authState is AuthUnauthenticated) {
        return Routes.login;
      }

      // No redirect needed
      return null;
    },
    routes: [
      // Splash / Loading screen
      GoRoute(
        path: Routes.splash,
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),

      // Authentication routes
      GoRoute(
        path: Routes.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: Routes.register,
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: Routes.emailVerification,
        name: 'emailVerification',
        builder: (context, state) => const EmailVerificationPage(),
      ),

      // Main app routes (authenticated)
      GoRoute(
        path: Routes.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: Routes.nearby,
        name: 'nearby',
        builder: (context, state) => BlocProvider(
          create: (_) => getIt<NearbyUsersBloc>(),
          child: const NearbyUsersScreen(),
        ),
      ),
      GoRoute(
        path: Routes.profile,
        name: 'profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: Routes.editProfile,
        name: 'editProfile',
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: Routes.bluetoothSettings,
        name: 'bluetoothSettings',
        builder: (context, state) => const BluetoothSettingsPage(),
      ),
      GoRoute(
        path: Routes.diagnosticsLogs,
        name: 'diagnosticsLogs',
        builder: (context, state) => const DiagnosticsLogsPage(),
      ),
      GoRoute(
        path: Routes.privacySettings,
        name: 'privacySettings',
        builder: (context, state) => const PrivacySettingsPage(),
      ),
      GoRoute(
        path: Routes.helpSupport,
        name: 'helpSupport',
        builder: (context, state) => const HelpSupportPage(),
      ),

      // Connection routes
      GoRoute(
        path: Routes.connections,
        name: 'connections',
        builder: (context, state) => const ConnectionsPage(),
      ),
      GoRoute(
        path: Routes.connectionRequests,
        name: 'connectionRequests',
        builder: (context, state) => const ConnectionRequestsScreen(),
      ),

      // Chat routes
      GoRoute(
        path: Routes.conversations,
        name: 'conversations',
        builder: (context, state) {
          final authState = context.read<AuthBloc>().state;
          final currentUserId =
              authState is AuthAuthenticated ? authState.user.id : '';

          return BlocProvider(
            create: (_) => getIt<ConversationsBloc>(),
            child: ConversationsScreen(
              currentUserId: currentUserId,
              onConversationTap: (conversation) {
                final otherUserId =
                    conversation.getOtherParticipantId(currentUserId);
                final otherInfo =
                    conversation.getOtherParticipantInfo(currentUserId);

                context.push(
                  Routes.chatWith(conversation.id),
                  extra: {
                    'currentUserId': currentUserId,
                    'otherUserId': otherUserId,
                    'otherUserName': otherInfo?.displayName ?? 'Unknown',
                    'otherUserPhotoUrl': otherInfo?.photoUrl,
                  },
                );
              },
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.chat,
        name: 'chat',
        builder: (context, state) {
          final conversationId = state.pathParameters['conversationId']!;
          final authState = context.read<AuthBloc>().state;
          final currentUserId =
              authState is AuthAuthenticated ? authState.user.id : '';

          final extra = state.extra as Map<String, dynamic>?;

          return BlocProvider(
            create: (_) => getIt<ChatBloc>(),
            child: ChatScreen(
              conversationId: conversationId,
              currentUserId: currentUserId,
              otherUserId: (extra?['otherUserId'] as String?) ?? '',
              otherUserName: (extra?['otherUserName'] as String?) ?? 'Unknown',
              otherUserPhotoUrl: extra?['otherUserPhotoUrl'] as String?,
            ),
          );
        },
      ),
    ],
  );
}
