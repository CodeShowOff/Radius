import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

import '../../../features/chat/presentation/bloc/conversations_bloc.dart';
import '../../../features/connections/presentation/bloc/connection_bloc.dart';
import '../../../features/location_groups/presentation/bloc/location_group_bloc.dart';
import '../../../features/profile/presentation/bloc/profile_bloc.dart';
import 'realtime_connection_service.dart';

/// Centralized manager for all real-time data streams in the app.
///
/// This service is responsible for:
/// 1. Initializing all real-time Firestore streams once on authentication
/// 2. Keeping streams alive throughout the app lifecycle
/// 3. Coordinating reconnection when network is restored
/// 4. Ensuring data is always fresh and available instantly on navigation
///
/// This eliminates the loading-on-every-navigation anti-pattern and provides
/// an industry-standard experience similar to WhatsApp, Slack, or Discord.
class RealTimeDataManager {
  final RealtimeConnectionService _connectionService;
  final ConnectionBloc _connectionBloc;
  final ConversationsBloc _conversationsBloc;
  final LocationGroupBloc _locationGroupBloc;
  final ProfileBloc _profileBloc;
  final Logger _logger;

  StreamSubscription<void>? _reconnectionSubscription;
  String? _currentUserId;
  bool _isInitialized = false;

  RealTimeDataManager({
    required RealtimeConnectionService connectionService,
    required ConnectionBloc connectionBloc,
    required ConversationsBloc conversationsBloc,
    required LocationGroupBloc locationGroupBloc,
    required ProfileBloc profileBloc,
    Logger? logger,
  })  : _connectionService = connectionService,
        _connectionBloc = connectionBloc,
        _conversationsBloc = conversationsBloc,
        _locationGroupBloc = locationGroupBloc,
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
      _logger.i('RealTimeDataManager already initialized for user $userId, updating info');
      updateUserInfo(userId: userId, displayName: displayName, photoUrl: photoUrl);
      return;
    }

    // If switching users, clean up first
    if (_isInitialized && _currentUserId != null && _currentUserId != userId) {
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
      return;
    }

    // Initialize connection monitoring (safe to call multiple times)
    await _connectionService.initialize();

    // Subscribe to reconnection events to refresh streams if needed
    await _reconnectionSubscription?.cancel();
    _reconnectionSubscription = _connectionService.onReconnection.listen((_) {
      _logger.i('Reconnection detected, streams will auto-refresh via Firestore');
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

    // 3. Load conversations (uses real-time Firestore streams)
    _conversationsBloc.add(ConversationsLoad(userId: userId));

    // 4. Load user's groups (uses real-time Firestore streams)
    // NOTE: The LocationGroupBloc streams will also wait for auth token internally
    _locationGroupBloc.add(LoadUserGroups(userId: userId));

    _isInitialized = true;
    _logger.i('RealTimeDataManager initialization complete');
  }

  /// Waits for the Firebase auth token to be available and valid.
  /// 
  /// This prevents race conditions where Firestore queries are executed
  /// before the auth token has propagated to the Firebase SDK.
  Future<bool> _waitForAuthToken(String userId, {int maxRetries = 5}) async {
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
        _logger.w('Auth user mismatch on attempt ${i + 1}: expected $userId, got ${currentUser?.uid}');
      }
      
      // Wait before retry with exponential backoff
      if (i < maxRetries - 1) {
        final delay = Duration(milliseconds: 100 * (i + 1));
        _logger.d('Waiting ${delay.inMilliseconds}ms before retry');
        await Future.delayed(delay);
      }
    }
    
    _logger.e('Failed to validate auth token for $userId after $maxRetries attempts');
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
  Future<void> signOut() async {
    _logger.i('Signing out from RealTimeDataManager');
    _currentUserId = null;
    _isInitialized = false;
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
