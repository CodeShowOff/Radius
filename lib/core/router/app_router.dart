import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/email_verification_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/chat/presentation/bloc/chat_bloc.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/conversations_screen.dart';
import '../../features/connections/presentation/pages/connection_requests_screen.dart';
import '../../features/connections/presentation/pages/connection_profile_page.dart';
import '../../features/connections/presentation/pages/connections_page.dart';
import '../../features/guess_me/guess_me.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/location_groups/presentation/bloc/group_chat_bloc.dart';
import '../../features/location_groups/presentation/pages/create_group_page.dart';
import '../../features/location_groups/presentation/pages/find_groups_page.dart';
import '../../features/location_groups/presentation/pages/group_chat_page.dart';
import '../../features/location_groups/presentation/pages/group_detail_page.dart';
import '../../features/location_groups/presentation/pages/my_groups_page.dart';
import '../../features/main_scaffold.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/bluetooth_settings_page.dart';
import '../../features/profile/presentation/pages/appearance_settings_page.dart';
import '../diagnostics/presentation/pages/diagnostics_logs_page.dart';
import '../../features/profile/presentation/pages/privacy_settings_page.dart';
import '../../features/profile/presentation/pages/help_support_page.dart';
import '../../features/proximity/presentation/pages/nearby_users_screen.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../config/app_config.dart';
import '../di/injection.dart';
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
  // Analytics removed - no navigation tracking
  return const [];
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

      // Main app routes (authenticated) with bottom navigation
      ShellRoute(
        builder: (context, state, child) {
          return MainScaffold(
            location: state.uri.path,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: Routes.home,
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomePage(),
            ),
          ),
          GoRoute(
            path: Routes.connections,
            name: 'connections',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ConnectionsPage(),
            ),
          ),
          GoRoute(
            path: Routes.myGroups,
            name: 'myGroups',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MyGroupsPage(),
            ),
          ),
        ],
      ),

      // Other routes without bottom navigation
      GoRoute(
        path: Routes.nearby,
        name: 'nearby',
        builder: (context, state) => const NearbyUsersScreen(),
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
        path: Routes.appearanceSettings,
        name: 'appearanceSettings',
        builder: (context, state) => const AppearanceSettingsPage(),
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

      // Connection requests route (connection details are within main connections page)
      GoRoute(
        path: Routes.connectionRequests,
        name: 'connectionRequests',
        builder: (context, state) => const ConnectionRequestsScreen(),
      ),
      GoRoute(
        path: Routes.userProfile,
        name: 'userProfile',
        builder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final extra = state.extra as Map<String, dynamic>?;

          return ConnectionProfilePage(
            otherUserId: userId,
            initialName: extra?['displayName'] as String?,
            initialPhotoUrl: extra?['photoUrl'] as String?,
          );
        },
      ),

      // Chat routes
      GoRoute(
        path: Routes.conversations,
        name: 'conversations',
        builder: (context, state) {
          final authState = context.read<AuthBloc>().state;
          final currentUserId =
              authState is AuthAuthenticated ? authState.user.id : '';

          return ConversationsScreen(
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

          // Use BlocProvider.value to use the existing singleton ChatBloc
          // instead of creating a new one on each navigation.
          // This enables instant navigation without loading spinners.
          return BlocProvider.value(
            value: getIt<ChatBloc>(),
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

      // GuessMe routes
      GoRoute(
        path: Routes.guessme,
        name: 'guessme',
        builder: (context, state) {
          return const GuessMeLobbyPage();
        },
      ),
      GoRoute(
        path: Routes.guessmeGame,
        name: 'guessmeGame',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final sessionId = extra?['sessionId'] as String? ?? '';

          return GuessMeGamePage(sessionId: sessionId);
        },
      ),

      // Location Groups routes
      GoRoute(
        path: Routes.locationGroups,
        name: 'locationGroups',
        builder: (context, state) {
          return const FindGroupsPage();
        },
      ),
      GoRoute(
        path: Routes.createLocationGroup,
        name: 'createLocationGroup',
        builder: (context, state) {
          return const CreateGroupPage();
        },
      ),
      GoRoute(
        path: Routes.locationGroupDetail,
        name: 'locationGroupDetail',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return BlocProvider.value(
            value: getIt<GroupChatBloc>(),
            child: GroupDetailPage(groupId: groupId),
          );
        },
      ),
      GoRoute(
        path: Routes.locationGroupChat,
        name: 'locationGroupChat',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return BlocProvider.value(
            value: getIt<GroupChatBloc>(),
            child: GroupChatPage(groupId: groupId),
          );
        },
      ),
    ],
  );
}
