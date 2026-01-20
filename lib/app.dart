import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/services/bluetooth/bluetooth_service.dart';
import 'core/services/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/chat/presentation/bloc/conversations_bloc.dart';
import 'features/connections/presentation/bloc/connection_bloc.dart';
import 'features/connections/presentation/widgets/connection_request_listener.dart';
import 'features/guess_me/presentation/bloc/guess_me_bloc.dart';
import 'features/location_groups/presentation/bloc/location_group_bloc.dart';
import 'features/profile/presentation/bloc/profile_bloc.dart';
import 'features/proximity/presentation/bloc/nearby_users_bloc.dart';

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
          // Conversations BLoC for chat list and unread counts (app-wide)
          BlocProvider<ConversationsBloc>(
            create: (_) => getIt<ConversationsBloc>(),
          ),
          // Profile BLoC for managing user profile app-wide
          BlocProvider<ProfileBloc>(
            create: (_) => getIt<ProfileBloc>(),
          ),
          // Nearby Users BLoC for BLE advertising (app-wide)
          BlocProvider<NearbyUsersBloc>(
            create: (_) => getIt<NearbyUsersBloc>(),
          ),

          // Guess Me BLoC (used by both lobby and game pages)
          BlocProvider<GuessmeBloc>(
            create: (_) => getIt<GuessmeBloc>(),
          ),

          // Location Groups BLoC (app-wide for preloading)
          BlocProvider<LocationGroupBloc>(
            create: (_) => getIt<LocationGroupBloc>(),
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

class _AuthAwareAppState extends State<_AuthAwareApp> {
  String? _currentUserId;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();

    // If the app starts already authenticated, BlocListener won't fire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onAuthChanged(context, context.read<AuthBloc>().state);
      _setupInAppNotifications();
    });
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
                  // TODO: Navigate to the conversation
                  // Will need context.go or Navigator to go to chat
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

      // Make sure profile data (including display name) starts loading as soon
      // as the user is authenticated, so HomePage can render the correct name
      // without requiring navigation to Profile first.
      if (userChanged) {
        try {
          context.read<ProfileBloc>().add(ProfileLoadRequested(newUserId));
        } catch (_) {
          // Ignore if ProfileBloc isn't available in the tree yet.
        }

        // Initialize ConnectionBloc to listen for connection requests
        // This preloads connections so the connections page loads instantly
        try {
          final profileBloc = context.read<ProfileBloc>();
          final connectionBloc = context.read<ConnectionBloc>();
          
          // Load connections immediately (profile info will be updated later)
          connectionBloc.add(ConnectionLoadAll(newUserId));
          
          // Listen for profile updates and update ConnectionBloc with display info
          profileBloc.stream.listen((profileState) {
            if (profileState is ProfileLoaded) {
              connectionBloc.setCurrentUser(
                userId: newUserId,
                displayName: profileState.profile.name,
                photoUrl: profileState.profile.photoUrl,
              );
            }
          });
        } catch (_) {
          // Ignore if blocs aren't available in the tree yet.
        }

        // Initialize ConversationsBloc to preload chats and unread counts
        try {
          context
              .read<ConversationsBloc>()
              .add(ConversationsLoad(userId: newUserId));
        } catch (_) {
          // Ignore if ConversationsBloc isn't available in the tree yet.
        }

        // Initialize LocationGroupBloc to preload user's groups
        // This preloads groups so the my groups page loads instantly
        try {
          final groupBloc = context.read<LocationGroupBloc>();
          groupBloc.add(LoadUserGroups(userId: newUserId));
        } catch (_) {
          // Ignore if bloc isn't available in the tree yet.
        }

        // Initialize BLE advertising to be discoverable
        try {
          context.read<NearbyUsersBloc>().add(NearbyUsersInitialize(
                userId: newUserId,
                username: state.user.username,
              ));
        } catch (_) {
          // Ignore if NearbyUsersBloc isn't available in the tree yet.
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
    if (_currentUserId != null) {
      // Clean up notifications on sign out
      try {
        getIt<NotificationService>().removeToken();
      } catch (_) {
        // Ignore if NotificationService isn't available.
      }
    }
    _currentUserId = null;
  }

  void _onProfileChanged(BuildContext context, ProfileState state) {
    if (state is ProfileLoaded && _currentUserId != null) {
      // Update the ConnectionBloc with user info when profile loads
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
