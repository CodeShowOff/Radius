import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';


import '../services/bluetooth/bluetooth_service.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/pages/email_verification_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';

import '../../features/chat/presentation/screens/chat_screen.dart';
import '../../features/chat/presentation/screens/conversations_screen.dart';
import '../../features/connections/presentation/pages/connection_requests_screen.dart';
import '../../features/connections/presentation/pages/all_requests_screen.dart';
import '../../features/connections/presentation/pages/connection_profile_page.dart';
import '../../features/connections/presentation/pages/connections_page.dart';
import '../../features/connections/presentation/pages/discovery_search_page.dart';
import '../../features/connections/presentation/pages/discovery_requests_screen.dart';
import '../../features/connections/presentation/bloc/discovery_bloc.dart';
import '../../features/home/presentation/pages/home_page.dart';

import '../../features/location_groups/presentation/pages/create_group_page.dart';
import '../../features/location_groups/presentation/pages/find_groups_page.dart';
import '../../features/location_groups/presentation/pages/group_chat_page.dart';
import '../../features/location_groups/presentation/pages/group_detail_page.dart';
import '../../features/location_groups/presentation/pages/my_groups_page.dart';
import '../../features/nearby_groups/presentation/bloc/nearby_group_bloc.dart';

import '../../features/nearby_groups/presentation/pages/create_nearby_group_page.dart';
import '../../features/nearby_groups/presentation/pages/discover_nearby_groups_page.dart';
import '../../features/nearby_groups/presentation/pages/nearby_group_chat_page.dart';
import '../../features/nearby_groups/presentation/pages/nearby_groups_page.dart';
import '../../features/nearby_help/presentation/bloc/nearby_help_bloc.dart';
import '../../features/nearby_help/presentation/pages/nearby_help_page.dart';
import '../../features/nearby_help/presentation/pages/nearby_help_settings_page.dart';
import '../../features/nearby_help/presentation/pages/create_help_request_page.dart';
import '../../features/nearby_help/presentation/pages/help_request_preview_page.dart';
import '../../features/nearby_help/presentation/pages/helper_navigation_page.dart';
import '../../features/nearby_help/presentation/pages/incoming_help_requests_page.dart';
import '../../features/random_chat/presentation/bloc/random_chat_bloc.dart';
import '../../features/random_chat/presentation/pages/random_chat_page.dart';
import '../../features/random_groups/presentation/bloc/random_group_bloc.dart';

import '../../features/random_groups/presentation/pages/create_random_group_page.dart';
import '../../features/random_groups/presentation/pages/discover_random_groups_page.dart';
import '../../features/random_groups/presentation/pages/random_group_chat_page.dart';
import '../../features/random_groups/presentation/pages/random_group_detail_page.dart';
import '../../features/random_groups/presentation/pages/random_group_settings_page.dart';
import '../../features/random_groups/presentation/pages/random_groups_page.dart';
import '../../features/main_scaffold.dart';
import '../../features/profile/presentation/pages/edit_profile_page.dart';
import '../../features/profile/presentation/pages/own_public_profile_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../features/posts/presentation/bloc/create_post_bloc.dart';
import '../../features/posts/presentation/bloc/post_feed_bloc.dart';
import '../../features/posts/presentation/pages/create_post_page.dart';
import '../../features/posts/presentation/pages/post_feed_page.dart';
import '../../features/local_news/presentation/bloc/create_news_post_bloc.dart';
import '../../features/local_news/presentation/bloc/news_feed_bloc.dart';
import '../../features/local_news/presentation/bloc/news_location_bloc.dart';
import '../../features/local_news/presentation/bloc/reels_feed_bloc.dart';
import '../../features/local_news/presentation/pages/create_news_post_page.dart';
import '../../features/local_news/presentation/pages/local_news_feed_page.dart';
import '../../features/local_news/presentation/pages/news_location_setup_page.dart';
import '../../features/local_news/presentation/pages/news_post_detail_page.dart';
import '../../features/local_news/domain/repositories/i_news_post_repository.dart';
import '../../features/profile/presentation/pages/bluetooth_settings_page.dart';
import '../../features/profile/presentation/pages/location_settings_page.dart';
import '../../features/profile/presentation/pages/appearance_settings_page.dart';
import '../../features/profile/presentation/pages/notification_settings_page.dart';
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
  // Include RouteObserver for route change detection
  return [
    getIt<RouteObserver<PageRoute>>(),
  ];
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
            path: Routes.localNews,
            name: 'localNewsTab',
            pageBuilder: (context, state) => NoTransitionPage(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider(create: (_) => getIt<NewsFeedBloc>()),
                  BlocProvider(create: (_) => getIt<ReelsFeedBloc>()),
                  BlocProvider.value(value: getIt<NewsLocationBloc>()),
                ],
                child: const LocalNewsFeedPage(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.postFeed,
            name: 'postFeedTab',
            pageBuilder: (context, state) => NoTransitionPage(
              child: BlocProvider(
                create: (_) => getIt<PostFeedBloc>(),
                child: const PostFeedPage(),
              ),
            ),
          ),
          GoRoute(
            path: Routes.profile,
            name: 'profileTab',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: OwnPublicProfilePage(),
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
        path: Routes.nearbyGroups,
        name: 'nearbyGroups',
        builder: (context, state) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: getIt<NearbyGroupBloc>()),
          ],
          child: const NearbyGroupsPage(),
        ),
      ),
      GoRoute(
        path: Routes.randomGroups,
        name: 'randomGroups',
        builder: (context, state) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: getIt<RandomGroupBloc>()),
          ],
          child: const RandomGroupsPage(),
        ),
      ),
      GoRoute(
        path: Routes.myGroups,
        name: 'myGroups',
        builder: (context, state) => const MyGroupsPage(),
      ),
      GoRoute(
        path: Routes.editProfile,
        name: 'editProfile',
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: Routes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: Routes.createPost,
        name: 'createPost',
        builder: (context, state) => BlocProvider(
          create: (_) => getIt<CreatePostBloc>(),
          child: const CreatePostPage(),
        ),
      ),

      // Local News routes
      GoRoute(
        path: Routes.localNewsSetup,
        name: 'localNewsSetup',
        builder: (context, state) {
          final authState = context.read<AuthBloc>().state;
          final userId =
              authState is AuthAuthenticated ? authState.user.id : '';
          return BlocProvider.value(
            value: getIt<NewsLocationBloc>(),
            child: NewsLocationSetupPage(userId: userId),
          );
        },
      ),
      GoRoute(
        path: Routes.localNewsCreate,
        name: 'localNewsCreate',
        builder: (context, state) => BlocProvider(
          create: (_) => getIt<CreateNewsPostBloc>(),
          child: const CreateNewsPostPage(),
        ),
      ),
      GoRoute(
        path: Routes.localNewsCreateReel,
        name: 'localNewsCreateReel',
        builder: (context, state) => BlocProvider(
          create: (_) => CreateNewsPostBloc(
            repository: getIt<INewsPostRepository>(),
            mediaService: getIt(),
            locationService: getIt(),
            mediaOptimizer: getIt(),
            newsPostService: getIt(),
            postType: 'reel',
          ),
          child: const CreateNewsPostPage(isReel: true),
        ),
      ),
      GoRoute(
        path: Routes.localNewsPost,
        name: 'localNewsPost',
        builder: (context, state) {
          final postId = state.pathParameters['postId']!;
          return RepositoryProvider.value(
            value: getIt<INewsPostRepository>(),
            child: NewsPostDetailPage(postId: postId),
          );
        },
      ),
      GoRoute(
        path: Routes.bluetoothSettings,
        name: 'bluetoothSettings',
        builder: (context, state) => const BluetoothSettingsPage(),
      ),
      GoRoute(
        path: Routes.locationSettings,
        name: 'locationSettings',
        builder: (context, state) => const LocationSettingsPage(),
      ),
      GoRoute(
        path: Routes.appearanceSettings,
        name: 'appearanceSettings',
        builder: (context, state) => const AppearanceSettingsPage(),
      ),
      GoRoute(
        path: Routes.notificationSettings,
        name: 'notificationSettings',
        builder: (context, state) => const NotificationSettingsPage(),
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
        path: Routes.allRequests,
        name: 'allRequests',
        builder: (context, state) => const AllRequestsScreen(),
      ),

      // Discovery routes (username-based user search & connection)
      GoRoute(
        path: Routes.discoverySearch,
        name: 'discoverySearch',
        builder: (context, state) => BlocProvider.value(
          value: getIt<DiscoveryBloc>(),
          child: const DiscoverySearchPage(),
        ),
      ),
      GoRoute(
        path: Routes.discoveryRequests,
        name: 'discoveryRequests',
        builder: (context, state) => BlocProvider.value(
          value: getIt<DiscoveryBloc>(),
          child: const DiscoveryRequestsScreen(),
        ),
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
            onConversationTap: (channel) {
              final otherMember = channel.state?.members.firstWhere(
                (m) => m.userId != currentUserId,
                orElse: () => channel.state!.members.first,
              );

              context.push(
                Routes.chatWith(channel.id!),
                extra: {
                  'currentUserId': currentUserId,
                  'otherUserId': otherMember?.userId ?? '',
                  'otherUserName': otherMember?.user?.name ?? 'Unknown',
                  'otherUserPhotoUrl': otherMember?.user?.image,
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

          return ChatScreen(
            conversationId: conversationId,
            currentUserId: currentUserId,
            otherUserId: (extra?['otherUserId'] as String?) ?? '',
            otherUserName: (extra?['otherUserName'] as String?) ?? 'Unknown',
            otherUserPhotoUrl: extra?['otherUserPhotoUrl'] as String?,
          );
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
          return GroupDetailPage(groupId: groupId);
        },
      ),
      GoRoute(
        path: Routes.locationGroupChat,
        name: 'locationGroupChat',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return GroupChatPage(groupId: groupId);
        },
      ),

      // Nearby Groups routes (Bluetooth-based proximity groups)
      GoRoute(
        path: Routes.discoverNearbyGroups,
        name: 'discoverNearbyGroups',
        builder: (context, state) {
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<NearbyGroupBloc>()),
            ],
            child: const DiscoverNearbyGroupsPage(),
          );
        },
      ),
      GoRoute(
        path: Routes.createNearbyGroup,
        name: 'createNearbyGroup',
        builder: (context, state) {
          return MultiRepositoryProvider(
            providers: [
              RepositoryProvider.value(value: getIt<BluetoothService>()),
            ],
            child: BlocProvider.value(
              value: getIt<NearbyGroupBloc>(),
              child: const CreateNearbyGroupPage(),
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.nearbyGroupChat,
        name: 'nearbyGroupChat',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<NearbyGroupBloc>()),
            ],
            child: NearbyGroupChatPage(groupId: groupId),
          );
        },
      ),

      // Random Groups routes (Admin-approved internet-based groups)
      GoRoute(
        path: Routes.discoverRandomGroups,
        name: 'discoverRandomGroups',
        builder: (context, state) {
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<RandomGroupBloc>()),
            ],
            child: const DiscoverRandomGroupsPage(),
          );
        },
      ),
      GoRoute(
        path: Routes.createRandomGroup,
        name: 'createRandomGroup',
        builder: (context, state) {
          return BlocProvider.value(
            value: getIt<RandomGroupBloc>(),
            child: const CreateRandomGroupPage(),
          );
        },
      ),
      GoRoute(
        path: Routes.randomGroupDetail,
        name: 'randomGroupDetail',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<RandomGroupBloc>()),
            ],
            child: RandomGroupDetailPage(groupId: groupId),
          );
        },
      ),
      GoRoute(
        path: Routes.randomGroupSettings,
        name: 'randomGroupSettings',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return BlocProvider.value(
            value: getIt<RandomGroupBloc>(),
            child: RandomGroupSettingsPage(groupId: groupId),
          );
        },
      ),
      GoRoute(
        path: Routes.randomGroupChat,
        name: 'randomGroupChat',
        builder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<RandomGroupBloc>()),
            ],
            child: RandomGroupChatPage(groupId: groupId),
          );
        },
      ),

      // Nearby Help routes
      GoRoute(
        path: Routes.nearbyHelp,
        name: 'nearbyHelp',
        builder: (context, state) {
          return BlocProvider.value(
            value: getIt<NearbyHelpBloc>(),
            child: const NearbyHelpPage(),
          );
        },
      ),

      // Random Chat route
      GoRoute(
        path: Routes.randomChat,
        name: 'randomChat',
        builder: (context, state) {
          return BlocProvider.value(
            value: getIt<RandomChatBloc>(),
            child: const RandomChatPage(),
          );
        },
      ),

      GoRoute(
        path: Routes.nearbyHelpSettings,
        name: 'nearbyHelpSettings',
        builder: (context, state) {
          return BlocProvider.value(
            value: getIt<NearbyHelpBloc>(),
            child: const NearbyHelpSettingsPage(),
          );
        },
      ),
      GoRoute(
        path: Routes.nearbyHelpCreateRequest,
        name: 'nearbyHelpCreateRequest',
        builder: (context, state) {
          return BlocProvider.value(
            value: getIt<NearbyHelpBloc>(),
            child: const CreateHelpRequestPage(),
          );
        },
      ),
      GoRoute(
        path: Routes.nearbyHelpIncomingRequests,
        name: 'nearbyHelpIncomingRequests',
        builder: (context, state) {
          // Get optional request ID from query parameters for highlighting
          final highlightRequestId = state.uri.queryParameters['requestId'];
          return BlocProvider.value(
            value: getIt<NearbyHelpBloc>(),
            child: IncomingHelpRequestsPage(
              highlightRequestId: highlightRequestId,
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.nearbyHelpRequestDetail,
        name: 'nearbyHelpRequestDetail',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId'];
          if (requestId == null || requestId.isEmpty) {
            // Return to nearby help page if no valid requestId
            return BlocProvider.value(
              value: getIt<NearbyHelpBloc>(),
              child: const NearbyHelpPage(),
            );
          }
          // Check for confirmAcceptance query parameter
          final confirmAcceptance = state.uri.queryParameters['confirmAcceptance'] == 'true';
          return BlocProvider.value(
            value: getIt<NearbyHelpBloc>(),
            child: HelpRequestPreviewPage(
              requestId: requestId,
              confirmAcceptance: confirmAcceptance,
            ),
          );
        },
      ),
      GoRoute(
        path: Routes.nearbyHelpHelperNavigation,
        name: 'nearbyHelpHelperNavigation',
        builder: (context, state) {
          final requestId = state.pathParameters['requestId'];
          if (requestId == null || requestId.isEmpty) {
            // Return to nearby help page if no valid requestId
            return BlocProvider.value(
              value: getIt<NearbyHelpBloc>(),
              child: const NearbyHelpPage(),
            );
          }
          return BlocProvider.value(
            value: getIt<NearbyHelpBloc>(),
            child: HelperNavigationPage(requestId: requestId),
          );
        },
      ),
    ],
  );
}
