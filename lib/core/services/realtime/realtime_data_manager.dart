import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

import '../../../features/chat/data/chat_preload_service.dart';
import '../../../features/chat/presentation/bloc/conversations_bloc.dart';
import '../../../features/connections/presentation/bloc/connection_bloc.dart';
import '../../../features/connections/presentation/bloc/discovery_bloc.dart';
import '../../../features/location_groups/data/group_chat_preload_service.dart';
import '../../../features/location_groups/presentation/bloc/location_group_bloc.dart';
import '../../../features/nearby_groups/presentation/bloc/nearby_group_bloc.dart';
import '../../../features/profile/presentation/bloc/profile_bloc.dart';
import '../../../features/random_groups/data/random_group_chat_preload_service.dart';
import '../../../features/random_groups/presentation/bloc/random_group_bloc.dart';
import '../presence/presence_service.dart';
import 'realtime_connection_service.dart';

/// Centralized manager for all real-time data streams in the app.
///
/// This service is responsible for:
/// 1. Initializing all real-time Firestore streams once on authentication
/// 2. Managing user presence via Firebase Realtime Database
/// 3. Keeping streams alive throughout the app lifecycle
/// 4. Coordinating reconnection when network is restored
/// 5. Ensuring data is always fresh and available instantly on navigation
///
/// Preloaded streams on app startup:
/// - User profile
/// - Connections
/// - Conversations
/// - Location groups (user's groups)
/// - Nearby groups (user's groups)
/// - Random groups (active groups + user's memberships)
///
/// This eliminates the loading-on-every-navigation anti-pattern and provides
/// an industry-standard experience similar to WhatsApp, Slack, or Discord.
class RealTimeDataManager {
  final RealtimeConnectionService _connectionService;
  final PresenceService? _presenceService;
  final ChatPreloadService? _chatPreloadService;
  final GroupChatPreloadService? _groupChatPreloadService;
  final RandomGroupChatPreloadService? _randomGroupChatPreloadService;
  final ConnectionBloc _connectionBloc;
  final DiscoveryBloc _discoveryBloc;
  final ConversationsBloc _conversationsBloc;
  final LocationGroupBloc _locationGroupBloc;
  final NearbyGroupBloc _nearbyGroupBloc;
  final RandomGroupBloc _randomGroupBloc;
  final ProfileBloc _profileBloc;
  final Logger _logger;

  StreamSubscription<void>? _reconnectionSubscription;
  String? _currentUserId;
  bool _isInitialized = false;
  bool _isInitializing = false; // Guard against concurrent initialization

  RealTimeDataManager({
    required RealtimeConnectionService connectionService,
    required ConnectionBloc connectionBloc,
    required DiscoveryBloc discoveryBloc,
    required ConversationsBloc conversationsBloc,
    required LocationGroupBloc locationGroupBloc,
    required NearbyGroupBloc nearbyGroupBloc,
    required RandomGroupBloc randomGroupBloc,
    required ProfileBloc profileBloc,
    PresenceService? presenceService,
    ChatPreloadService? chatPreloadService,
    GroupChatPreloadService? groupChatPreloadService,
    RandomGroupChatPreloadService? randomGroupChatPreloadService,
    Logger? logger,
  })  : _connectionService = connectionService,
        _presenceService = presenceService,
        _chatPreloadService = chatPreloadService,
        _groupChatPreloadService = groupChatPreloadService,
        _randomGroupChatPreloadService = randomGroupChatPreloadService,
        _connectionBloc = connectionBloc,
        _discoveryBloc = discoveryBloc,
        _conversationsBloc = conversationsBloc,
        _locationGroupBloc = locationGroupBloc,
        _nearbyGroupBloc = nearbyGroupBloc,
        _randomGroupBloc = randomGroupBloc,
        _profileBloc = profileBloc,
        _logger = logger ?? Logger();

  /// Whether the manager has been initialized for a user.
  bool get isInitialized => _isInitialized;

  /// The current user ID that streams are initialized for.
  String? get currentUserId => _currentUserId;

  /// Current connection status.
  RealtimeConnectionStatus get connectionStatus => _connectionService.status;

  /// Stream of connection status changes.
  Stream<RealtimeConnectionStatus> get connectionStatusStream =>
      _connectionService.statusStream;

  /// Access to presence service for watching other users' online status.
  PresenceService? get presenceService => _presenceService;

  /// Initialize all real-time streams for a user.
  ///
  /// This should be called once when the user authenticates.
  /// The streams will remain active until [dispose] is called.
  ///
  /// IMPORTANT: This method waits for the auth token to be ready before
  /// initializing Firestore streams to prevent PERMISSION_DENIED errors.
  Future<void> initializeForUser({
    required String userId,
    String? displayName,
    String? photoUrl,
  }) async {
    // If same user and already initialized, just update user info
    if (_isInitialized && _currentUserId == userId) {
      _logger.i(
          'RealTimeDataManager already initialized for user $userId, updating info');
      updateUserInfo(
          userId: userId, displayName: displayName, photoUrl: photoUrl);
      return;
    }

    // Guard: Prevent concurrent initialization
    if (_isInitializing) {
      _logger.w(
          'RealTimeDataManager initialization already in progress, skipping');
      return;
    }
    _isInitializing = true;

    try {
      // If switching users, clean up first
      if (_isInitialized &&
          _currentUserId != null &&
          _currentUserId != userId) {
        _logger.i('User changed from $_currentUserId to $userId, cleaning up');
        await signOut();
      }

      _logger.i('Initializing RealTimeDataManager for user $userId');
      _currentUserId = userId;

      // CRITICAL: Wait for auth token to be ready before starting Firestore streams
      // This prevents race conditions where queries run before token propagation
      final isAuthReady = await _waitForAuthToken(userId);
      if (!isAuthReady) {
        _logger.e('Auth token not ready, aborting initialization');
        _currentUserId = null;
        _isInitializing = false;
        return;
      }

      // Initialize connection monitoring (safe to call multiple times)
      await _connectionService.initialize();

      // Subscribe to reconnection events to refresh streams if needed
      await _reconnectionSubscription?.cancel();
      _reconnectionSubscription = _connectionService.onReconnection.listen((_) {
        _logger.i(
            'Reconnection detected, streams will auto-refresh via Firestore');
        // Firestore streams automatically reconnect, but we can force refresh if needed
      });

      // Initialize all BLoCs with persistent streams
      // These calls are idempotent - they won't reload if already loaded for this user

      // 1. Load profile first (needed for display names in other features)
      _profileBloc.add(ProfileLoadRequested(userId));

      // 2. Load connections (uses real-time Firestore streams)
      _connectionBloc.setCurrentUser(
        userId: userId,
        displayName: displayName,
        photoUrl: photoUrl,
      );
      _connectionBloc.add(ConnectionLoadAll(
        userId,
        displayName: displayName,
        photoUrl: photoUrl,
      ));

      // 2b. Load discovery connection requests (uses real-time Firestore streams)
      _discoveryBloc.setCurrentUser(
        userId: userId,
        displayName: displayName,
        photoUrl: photoUrl,
      );
      _discoveryBloc.add(DiscoveryLoadRequests(
        userId,
        displayName: displayName,
        photoUrl: photoUrl,
      ));

      // 3. Load conversations (uses real-time Firestore streams)
      _conversationsBloc.add(ConversationsLoad(userId: userId));

      // 4. Load user's groups (uses real-time Firestore streams)
      // NOTE: The LocationGroupBloc streams will also wait for auth token internally
      _locationGroupBloc.add(LoadUserGroups(userId: userId));

      // 4b. Load user's nearby groups (uses real-time Firestore streams)
      _nearbyGroupBloc.add(WatchUserNearbyGroups(userId));
      _nearbyGroupBloc.add(LoadUserActiveGroup(userId));

      // 5. Load random groups (uses real-time Firestore streams)
      // Preload both active groups (for discovery) and user's memberships
      // This ensures instant loading when user navigates to random groups page
      _randomGroupBloc.add(WatchActiveRandomGroups());
      _randomGroupBloc.add(WatchUserRandomGroups(userId));

      // 6. Initialize presence tracking (online/offline status via Firebase RTDB)
      // This enables WhatsApp-style "last seen" and online indicators
      // Non-blocking: presence is non-critical and should not delay preloading
      _initPresence(userId);

      _isInitialized = true;
      _logger.i('RealTimeDataManager initialization complete');

      // 7. Preload recent/unread chats in the background (non-blocking)
      // This warms the cache so first chat opens are instant
      _triggerChatPreload(userId);

      // 8. Preload recent group chats in the background (non-blocking)
      // This warms the group chat cache so group chats open instantly
      _triggerGroupChatPreload(userId);

      // 9. Preload recent random group chats in the background (non-blocking)
      // This warms the random group chat cache so random group chats open instantly
      _triggerRandomGroupChatPreload(userId);
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize presence tracking in the background (non-blocking).
  void _initPresence(String userId) {
    if (_presenceService == null) return;
    Future.microtask(() async {
      try {
        await _presenceService.initialize(userId);
        _logger.i('Presence service initialized for user $userId');
      } catch (e) {
        _logger.e('Failed to initialize presence service', error: e);
        // Presence is non-critical, continue without it
      }
    });
  }

  /// Trigger chat preloading in the background.
  /// This is non-blocking and will not affect UI rendering.
  void _triggerChatPreload(String userId) {
    if (_chatPreloadService == null) {
      _logger.d('Chat preload service not available, skipping preload');
      return;
    }

    // Run preload asynchronously without awaiting
    // This ensures UI is not blocked during startup
    Future.microtask(() async {
      try {
        await _chatPreloadService.preloadOnStartup(userId);
      } catch (e) {
        _logger.e('Chat preload failed', error: e);
        // Preload failures are silent - don't affect UX
      }
    });
  }

  /// Trigger group chat preloading in the background.
  /// This is non-blocking and will not affect UI rendering.
  void _triggerGroupChatPreload(String userId) {
    if (_groupChatPreloadService == null) {
      _logger.d('Group chat preload service not available, skipping preload');
      return;
    }

    // Run preload asynchronously without awaiting
    // This ensures UI is not blocked during startup
    Future.microtask(() async {
      try {
        await _groupChatPreloadService.preloadOnStartup(userId);
      } catch (e) {
        _logger.e('Group chat preload failed', error: e);
        // Preload failures are silent - don't affect UX
      }
    });
  }

  /// Trigger random group chat preloading in the background.
  /// This is non-blocking and will not affect UI rendering.
  void _triggerRandomGroupChatPreload(String userId) {
    if (_randomGroupChatPreloadService == null) {
      _logger
          .d('Random group chat preload service not available, skipping preload');
      return;
    }

    // Run preload asynchronously without awaiting
    // This ensures UI is not blocked during startup
    Future.microtask(() async {
      try {
        await _randomGroupChatPreloadService.preloadOnStartup(userId);
      } catch (e) {
        _logger.e('Random group chat preload failed', error: e);
        // Preload failures are silent - don't affect UX
      }
    });
  }

  /// Waits for the Firebase auth token to be available and valid.
  ///
  /// This prevents race conditions where Firestore queries are executed
  /// before the auth token has propagated to the Firebase SDK.
  Future<bool> _waitForAuthToken(String userId, {int maxRetries = 2}) async {
    final auth = FirebaseAuth.instance;

    for (int i = 0; i < maxRetries; i++) {
      final currentUser = auth.currentUser;
      if (currentUser != null && currentUser.uid == userId) {
        try {
          // Force token refresh to ensure it's valid and propagated
          final token = await currentUser.getIdToken(false);
          if (token != null && token.isNotEmpty) {
            _logger.i('Auth token validated on attempt ${i + 1}');
            return true;
          }
        } catch (e) {
          _logger.w('Token validation failed on attempt ${i + 1}', error: e);
        }
      } else {
        _logger.w(
            'Auth user mismatch on attempt ${i + 1}: expected $userId, got ${currentUser?.uid}');
      }

      // Wait before retry with exponential backoff
      if (i < maxRetries - 1) {
        final delay = Duration(milliseconds: 100 * (i + 1));
        _logger.d('Waiting ${delay.inMilliseconds}ms before retry');
        await Future.delayed(delay);
      }
    }

    _logger.e(
        'Failed to validate auth token for $userId after $maxRetries attempts');
    return false;
  }

  /// Update user profile info (e.g., when profile is loaded).
  void updateUserInfo({
    required String userId,
    String? displayName,
    String? photoUrl,
  }) {
    if (_currentUserId != userId) return;

    _connectionBloc.setCurrentUser(
      userId: userId,
      displayName: displayName,
      photoUrl: photoUrl,
    );
  }

  /// Force refresh all streams (e.g., after a long background period).
  void refreshAllStreams() {
    if (!_isInitialized || _currentUserId == null) return;

    _logger.i('Force refreshing all real-time streams');
    _connectionService.forceReconnect();
  }

  /// Clean up when user signs out.
  ///
  /// CRITICAL: This cancels all Firestore stream subscriptions in blocs
  /// BEFORE Firebase Auth signs out, preventing PERMISSION_DENIED errors.
  Future<void> signOut() async {
    _logger.i('Signing out from RealTimeDataManager');

    // Cancel all Firestore stream subscriptions FIRST, before auth sign-out.
    // These blocs hold active Firestore listeners that will throw
    // PERMISSION_DENIED if the auth token is revoked while they're active.
    _connectionBloc.add(const ConnectionReset());
    _discoveryBloc.add(const DiscoveryReset());
    _conversationsBloc.add(const ConversationsReset());
    _locationGroupBloc.add(const ResetGroupState());
    _nearbyGroupBloc.add(const ResetNearbyGroupState());
    _randomGroupBloc.add(const ResetRandomGroupState());

    // Dispose presence service (sets user offline)
    try {
      await _presenceService?.dispose();
    } catch (e) {
      _logger.e('Error disposing presence service', error: e);
    }

    // Clear chat preload tracking
    _chatPreloadService?.clear();
    _groupChatPreloadService?.clear();
    _randomGroupChatPreloadService?.clear();

    _currentUserId = null;
    _isInitialized = false;
    _isInitializing = false;
    await _reconnectionSubscription?.cancel();
    _reconnectionSubscription = null;
  }

  /// Dispose of all resources.
  Future<void> dispose() async {
    await signOut();
    await _connectionService.dispose();
    _logger.i('RealTimeDataManager disposed');
  }
}
