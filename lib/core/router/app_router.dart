import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/chat/presentation/bloc/chat_bloc.dart';
import '../../features/chat/presentation/bloc/conversations_bloc.dart';
import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/conversations_screen.dart';
import '../../features/connections/presentation/bloc/connection_bloc.dart';
import '../../features/connections/presentation/pages/connection_requests_screen.dart';
import '../../features/connections/presentation/pages/connections_list_screen.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/profile/presentation/bloc/profile_bloc.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../features/proximity/presentation/pages/nearby_users_screen.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../config/app_config.dart';
import '../di/injection.dart';
import '../services/analytics/analytics_service.dart';
import 'routes.dart';

/// Analytics observer for tracking screen views.
/// Only active when analytics is enabled in the current environment.
final _analyticsObserver = AppConfig.enableAnalytics
    ? getIt<AnalyticsService>().observer
    : null;

/// Application router configuration using GoRouter.
/// 
/// Defines all navigation routes and their corresponding pages.
final GoRouter appRouter = GoRouter(
  initialLocation: Routes.splash,
  debugLogDiagnostics: AppConfig.enableLogging,
  observers: [
    if (_analyticsObserver != null) _analyticsObserver!,
  ],
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
      builder: (context, state) => BlocProvider(
        create: (_) => getIt<ProfileBloc>(),
        child: const EditProfilePage(),
      ),
    ),
    
    // Connection routes
    GoRoute(
      path: Routes.connections,
      name: 'connections',
      builder: (context, state) => BlocProvider(
        create: (_) => getIt<ConnectionBloc>(),
        child: const ConnectionsListScreen(),
      ),
    ),
    GoRoute(
      path: Routes.connectionRequests,
      name: 'connectionRequests',
      builder: (context, state) => BlocProvider(
        create: (_) => getIt<ConnectionBloc>(),
        child: const ConnectionRequestsScreen(),
      ),
    ),
    
    // Chat routes
    GoRoute(
      path: Routes.conversations,
      name: 'conversations',
      builder: (context, state) {
        // currentUserId should be passed via extra or retrieved from auth state
        final extra = state.extra as Map<String, dynamic>?;
        final currentUserId = extra?['currentUserId'] as String? ?? '';
        
        return BlocProvider(
          create: (_) => getIt<ConversationsBloc>(),
          child: ConversationsScreen(
            currentUserId: currentUserId,
            onConversationTap: (conversation) {
              final otherUserId = conversation.getOtherParticipantId(currentUserId);
              final otherInfo = conversation.getOtherParticipantInfo(currentUserId);
              
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
        final extra = state.extra as Map<String, dynamic>?;
        
        return BlocProvider(
          create: (_) => getIt<ChatBloc>(),
          child: ChatScreen(
            conversationId: conversationId,
            currentUserId: extra?['currentUserId'] ?? '',
            otherUserId: extra?['otherUserId'] ?? '',
            otherUserName: extra?['otherUserName'] ?? 'Unknown',
            otherUserPhotoUrl: extra?['otherUserPhotoUrl'],
          ),
        );
      },
    ),
  ],
  
  // TODO: Add redirect logic for authentication
  // redirect: (context, state) {
  //   final isAuthenticated = // check auth state
  //   final isAuthRoute = state.matchedLocation == Routes.login || 
  //                       state.matchedLocation == Routes.register;
  //   
  //   if (!isAuthenticated && !isAuthRoute) {
  //     return Routes.login;
  //   }
  //   if (isAuthenticated && isAuthRoute) {
  //     return Routes.home;
  //   }
  //   return null;
  // },
);
