import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/router/routes.dart';
import 'core/services/bluetooth/bluetooth_service.dart';
import 'core/services/notifications/notification_service.dart';
import 'core/services/realtime/realtime_data_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/chat/presentation/bloc/conversations_bloc.dart';
import 'features/connections/presentation/bloc/connection_bloc.dart';
import 'features/connections/presentation/bloc/discovery_bloc.dart';
import 'features/connections/presentation/widgets/connection_request_listener.dart';
import 'features/location_groups/presentation/bloc/location_group_bloc.dart';
import 'features/profile/presentation/bloc/profile_bloc.dart';
import 'features/proximity/presentation/bloc/nearby_users_bloc.dart';
import 'features/random_chat/presentation/bloc/random_chat_bloc.dart';
import 'features/random_groups/presentation/bloc/random_group_bloc.dart';

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
          // Discovery BLoC for username-based user search and connection requests
          BlocProvider<DiscoveryBloc>(
            create: (_) => getIt<DiscoveryBloc>(),
          ),
          // Conversations BLoC for chat list and unread counts (app-wide)
          BlocProvider<ConversationsBloc>(
            create: (_) => getIt<ConversationsBloc>(),
          ),
          // Random Chat BLoC for managing random chat connections (app-wide)
          BlocProvider<RandomChatBloc>(
            create: (_) => getIt<RandomChatBloc>(),
          ),
          // Profile BLoC for managing user profile app-wide
          BlocProvider<ProfileBloc>(
            create: (_) => getIt<ProfileBloc>(),
          ),
          // Nearby Users BLoC for BLE advertising (app-wide)
          BlocProvider<NearbyUsersBloc>(
            create: (_) => getIt<NearbyUsersBloc>(),
          ),

          // Location Groups BLoC (app-wide for preloading)
          BlocProvider<LocationGroupBloc>(
            create: (_) => getIt<LocationGroupBloc>(),
          ),

          // Random Groups BLoC (app-wide for preloading)
          BlocProvider<RandomGroupBloc>(
            create: (_) => getIt<RandomGroupBloc>(),
          ),

          // Theme settings
          BlocProvider<ThemeCubit>(
            create: (_) => getIt<ThemeCubit>(),
          ),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return _AuthAwareApp(
              child: MaterialApp.router(
                title: 'Radius',
                debugShowCheckedModeBanner: false,

                // Theme configuration
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeMode,

                // Router configuration
                routerConfig: appRouter,

                // Builder to add app-wide listeners (like connection request notifications)
                builder: (context, child) {
                  return ConnectionRequestListener(
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Listens to auth state and triggers profile loading and BLE advertising on authentication.
///
/// BLE advertising starts app-wide when user authenticates to be discoverable.
/// Scanning remains screen-specific (Nearby Users screen).
class _AuthAwareApp extends StatefulWidget {
  final Widget child;

  const _AuthAwareApp({required this.child});

  @override
  State<_AuthAwareApp> createState() => _AuthAwareAppState();
}

class _AuthAwareAppState extends State<_AuthAwareApp>
    with WidgetsBindingObserver {
  String? _currentUserId;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();

    // Listen for app lifecycle changes (background/foreground)
    WidgetsBinding.instance.addObserver(this);

    // If the app starts already authenticated, BlocListener won't fire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onAuthChanged(context, context.read<AuthBloc>().state);
      _setupInAppNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('[RadiusApp] App lifecycle changed to: $state');
    debugPrint('[RadiusApp] User authenticated: ${_currentUserId != null}');

    // When app resumes (user returns from home screen after turning on Bluetooth)
    // restart advertising if user is authenticated
    if (state == AppLifecycleState.resumed && _currentUserId != null) {
      debugPrint('[RadiusApp] ⚡ App RESUMED - restarting BLE advertising');
      try {
        context.read<NearbyUsersBloc>().add(const NearbyUsersAppResumed());
        debugPrint('[RadiusApp] ✓ BLE advertising restart event sent');
      } catch (e) {
        debugPrint('[RadiusApp] ✗ Failed to restart advertising: $e');
      }
    } else if (state == AppLifecycleState.paused) {
      debugPrint(
          '[RadiusApp] 📱 App PAUSED (backgrounded) - advertising continues in background');
    } else if (state == AppLifecycleState.inactive) {
      debugPrint('[RadiusApp] ⏸️ App INACTIVE');
    } else if (state == AppLifecycleState.detached) {
      debugPrint('[RadiusApp] 🔌 App DETACHED');
    }
  }

  /// Setup in-app notification handler for foreground messages
  void _setupInAppNotifications() {
    try {
      final notificationService = getIt<NotificationService>();
      notificationService.onInAppNotification = (title, body, data) {
        // Show SnackBar for new messages when user is not viewing that chat
        if (mounted) {
          _scaffoldMessengerKey.currentState?.clearSnackBars();
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.message, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (body.isNotEmpty)
                          Text(
                            body,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.primary,
              action: SnackBarAction(
                label: 'VIEW',
                textColor: Colors.white,
                onPressed: () {
                  final type = data['type'] as String?;
                  final conversationId = data['conversationId'] as String?;
                  final groupId = data['groupId'] as String?;

                  // Navigate to the correct screen based on message type.
                  // Use push() instead of go() to prevent race condition:
                  // go() replaces the current route, which can cause the old
                  // screen's dispose() to clear the notification context
                  // AFTER the new screen's initState() sets it.
                  if (type == 'group_message' && groupId != null) {
                    appRouter.push(Routes.locationGroupChatWith(groupId));
                  } else if (type == 'nearby_group_message' && groupId != null) {
                    appRouter.push(Routes.nearbyGroupChatWith(groupId));
                  } else if (type == 'random_group_message' && groupId != null) {
                    appRouter.push(Routes.randomGroupChatWith(groupId));
                  } else if (conversationId != null) {
                    appRouter.push(Routes.chatWith(conversationId));
                  }
                },
              ),
            ),
          );
        }
      };
    } catch (_) {
      // Service not available
    }
  }

  void _onAuthChanged(BuildContext context, AuthState state) {
    if (state is AuthAuthenticated) {
      final newUserId = state.user.id;
      final userChanged = _currentUserId != newUserId;
      _currentUserId = newUserId;

      // Initialize all real-time data streams via the centralized manager
      // This ensures persistent connections and instant navigation
      if (userChanged) {
        try {
          // Use RealTimeDataManager for centralized stream management
          // This initializes: Profile, Connections, Conversations, and Groups
          // All streams are persistent and won't reload on navigation
          getIt<RealTimeDataManager>().initializeForUser(
            userId: newUserId,
            displayName: state.user.displayName,
            photoUrl: state.user.avatarUrl,
          );
        } catch (_) {
          // Fallback to individual BLoC initialization if manager not available
          _initializeBlocsManually(context, newUserId, state);
        }

        // Initialize BLE advertising to be discoverable
        // This is CRITICAL for proximity features - log failures for debugging
        try {
          final nearbyUsersBloc = context.read<NearbyUsersBloc>();
          nearbyUsersBloc.add(NearbyUsersInitialize(
            userId: newUserId,
            username: state.user.username,
          ));
          debugPrint(
              '[RadiusApp] ✓ BLE advertising initialization started for ${state.user.username}');
        } catch (e) {
          // This should never happen since NearbyUsersBloc is provided globally
          debugPrint(
              '[RadiusApp] ✗✗✗ CRITICAL: Failed to initialize BLE advertising: $e');
          debugPrint(
              '[RadiusApp] This means the user will NOT be discoverable!');
        }

        // Initialize push notifications
        try {
          getIt<NotificationService>().initialize(newUserId);
        } catch (_) {
          // Ignore if NotificationService isn't available yet.
        }
      }
      return;
    }

    // Signed out or unauthenticated.
    // Skip cleanup if AuthLoading — the AuthBloc._onSignOutRequested is still
    // running its own cleanup. Only run fallback cleanup on final states.
    if (state is AuthLoading) return;

    if (_currentUserId != null) {
      // Normal sign-out path: AuthBloc._onSignOutRequested already called
      // RealTimeDataManager.signOut() (which cancelled all 7 bloc subscriptions,
      // dispatched reset events, disposed presence, and cleared preload caches),
      // then removed FCM token and cleared local data — all BEFORE Firebase Auth
      // signed out. So by the time we get here, cleanup is already complete.
      //
      // Edge-case fallback: If we arrive here WITHOUT AuthBloc having run
      // (e.g., token expiry or forced server-side sign-out), RTDM will still
      // be in "initialized" state. In that case, do a best-effort cleanup.
      // Note: auth is already revoked in this path, so Firestore writes will
      // fail — but cancelling local subscriptions and resetting state is safe.
      try {
        final rtdm = getIt<RealTimeDataManager>();
        if (rtdm.isInitialized) {
          rtdm.signOut(); // fire-and-forget; auth is already gone
        }
      } catch (_) {}

      // Reset RandomChatBloc (not managed by RTDM)
      try { getIt<RandomChatBloc>().add(const ResetRandomChatState()); } catch (_) {}
    }
    _currentUserId = null;
  }

  /// Fallback method for manual BLoC initialization if RealTimeDataManager fails.
  ///
  /// This method waits for auth token validation before starting Firestore streams
  /// to prevent PERMISSION_DENIED race conditions.
  Future<void> _initializeBlocsManually(
      BuildContext context, String userId, AuthAuthenticated state) async {
    // Capture bloc references BEFORE any async operation to avoid context issues
    ProfileBloc? profileBloc;
    ConnectionBloc? connectionBloc;
    ConversationsBloc? conversationsBloc;
    LocationGroupBloc? locationGroupBloc;

    try {
      profileBloc = context.read<ProfileBloc>();
    } catch (_) {}

    try {
      connectionBloc = context.read<ConnectionBloc>();
    } catch (_) {}

    try {
      conversationsBloc = context.read<ConversationsBloc>();
    } catch (_) {}

    try {
      locationGroupBloc = context.read<LocationGroupBloc>();
    } catch (_) {}

    // Re-enable Firestore network if it was disabled during sign-out.
    try {
      await FirebaseFirestore.instance.enableNetwork();
    } catch (_) {}

    // CRITICAL: Wait for auth token to be ready before starting Firestore streams
    // This prevents race conditions where streams start before token propagation
    final isAuthReady = await _waitForAuthToken(userId);
    if (!isAuthReady) {
      // Auth token not ready - don't start streams yet
      return;
    }

    // Now use the captured bloc references (no context needed)
    profileBloc?.add(ProfileLoadRequested(userId));

    if (connectionBloc != null) {
      final capturedConnectionBloc = connectionBloc; // Capture for closure
      capturedConnectionBloc.add(ConnectionLoadAll(userId));
      profileBloc?.stream.listen((profileState) {
        if (profileState is ProfileLoaded) {
          capturedConnectionBloc.setCurrentUser(
            userId: userId,
            displayName: profileState.profile.name,
            photoUrl: profileState.profile.photoUrl,
          );
        }
      });
    }

    conversationsBloc?.add(ConversationsLoad(userId: userId));
    locationGroupBloc?.add(LoadUserGroups(userId: userId));
  }

  /// Waits for the Firebase auth token to be available and valid.
  /// This is the fallback path (only used if RealTimeDataManager fails).
  Future<bool> _waitForAuthToken(String userId, {int maxRetries = 3}) async {
    final auth = FirebaseAuth.instance;

    for (int i = 0; i < maxRetries; i++) {
      final currentUser = auth.currentUser;
      if (currentUser != null && currentUser.uid == userId) {
        try {
          final token = await currentUser.getIdToken(false);
          if (token != null && token.isNotEmpty) {
            return true;
          }
        } catch (_) {}
      }

      if (i < maxRetries - 1) {
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }

    return false;
  }

  void _onProfileChanged(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded && _currentUserId != null) {
      // Update user info via the centralized RealTimeDataManager
      try {
        getIt<RealTimeDataManager>().updateUserInfo(
          userId: _currentUserId!,
          displayName: state.profile.name,
          photoUrl: state.profile.photoUrl,
        );
      } catch (_) {
        // Fallback: Update ConnectionBloc directly
        try {
          context.read<ConnectionBloc>().setCurrentUser(
                userId: _currentUserId!,
                displayName: state.profile.name,
                photoUrl: state.profile.photoUrl,
              );
        } catch (_) {
          // Ignore if ConnectionBloc isn't available in the tree yet.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
          listener: _onAuthChanged,
        ),
        BlocListener<ProfileBloc, ProfileState>(
          listener: _onProfileChanged,
        ),
      ],
      child: ScaffoldMessenger(
        key: _scaffoldMessengerKey,
        child: widget.child,
      ),
    );
  }
}
