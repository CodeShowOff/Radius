import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';

/// User presence status.
enum PresenceStatus {
  /// User is currently online.
  online,

  /// User is away (app in background).
  away,

  /// User is offline.
  offline,
}

/// Data class representing a user's presence state.
class PresenceState {
  final PresenceStatus status;
  final DateTime lastSeen;

  const PresenceState({
    required this.status,
    required this.lastSeen,
  });

  factory PresenceState.fromRtdb(Map<dynamic, dynamic>? data) {
    if (data == null) {
      // Use a very old timestamp (1 year ago) for users with no presence data
      // This prevents showing "Last seen just now" for users who've never been online
      return PresenceState(
        status: PresenceStatus.offline,
        lastSeen: DateTime.now().subtract(const Duration(days: 365)),
      );
    }

    final state = data['state'] as String? ?? 'offline';
    final lastSeenMs = data['lastSeen'] as int? ?? DateTime.now().subtract(const Duration(days: 365)).millisecondsSinceEpoch;

    return PresenceState(
      status: _parseStatus(state),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeenMs),
    );
  }

  static PresenceStatus _parseStatus(String state) {
    switch (state) {
      case 'online':
        return PresenceStatus.online;
      case 'away':
        return PresenceStatus.away;
      default:
        return PresenceStatus.offline;
    }
  }

  bool get isOnline => status == PresenceStatus.online;
  bool get isAway => status == PresenceStatus.away;
  bool get isOffline => status == PresenceStatus.offline;

  /// Returns a human-readable string for the presence status.
  String get displayText {
    switch (status) {
      case PresenceStatus.online:
        return 'Online';
      case PresenceStatus.away:
        return 'Away';
      case PresenceStatus.offline:
        return _formatLastSeen();
    }
  }

  String _formatLastSeen() {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) {
      return 'Last seen just now';
    } else if (diff.inMinutes < 60) {
      return 'Last seen ${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return 'Last seen ${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return 'Last seen ${diff.inDays}d ago';
    } else {
      return 'Last seen a while ago';
    }
  }
}

/// Service for tracking user presence using Firebase Realtime Database.
///
/// This service implements the industry-standard presence pattern:
/// 1. Uses RTDB for presence (supports onDisconnect)
/// 2. Syncs to Firestore for chat UI display
/// 3. Handles app lifecycle (foreground/background)
///
/// RTDB Structure:
/// ```
/// status/
///   {userId}/
///     state: "online" | "away" | "offline"
///     lastSeen: timestamp (milliseconds)
/// ```
///
/// Why RTDB instead of Firestore?
/// - RTDB has `onDisconnect()` which automatically triggers when the client
///   disconnects (app close, crash, network loss, etc.)
/// - Firestore does NOT have this capability
/// - This ensures accurate offline detection without relying on heartbeats
class PresenceService with WidgetsBindingObserver {
  final FirebaseDatabase _rtdb;
  final FirebaseFirestore _firestore;
  final Logger _logger;

  String? _currentUserId;
  DatabaseReference? _userStatusRef;
  DatabaseReference? _connectedRef;
  StreamSubscription<DatabaseEvent>? _connectedSubscription;

  /// Cache of presence states for other users.
  final Map<String, PresenceState> _presenceCache = {};

  /// Stream subscriptions for other users' presence.
  final Map<String, StreamSubscription<DatabaseEvent>> _presenceSubscriptions = {};

  /// Stream controller for broadcasting presence updates.
  final _presenceController = StreamController<Map<String, PresenceState>>.broadcast();

  bool _isInitialized = false;
  bool _isInitializing = false; // Guard against concurrent initialization

  PresenceService({
    FirebaseDatabase? rtdb,
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _rtdb = rtdb ?? FirebaseDatabase.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  /// Stream of presence updates for watched users.
  Stream<Map<String, PresenceState>> get presenceUpdates => _presenceController.stream;

  /// Get cached presence for a user (may be stale, use watchPresence for live updates).
  PresenceState? getCachedPresence(String userId) => _presenceCache[userId];

  /// Initialize presence tracking for the current user.
  Future<void> initialize(String userId) async {
    if (_isInitialized && _currentUserId == userId) {
      _logger.d('Presence already initialized for user $userId');
      return;
    }

    // Guard: Prevent concurrent initialization
    if (_isInitializing) {
      _logger.w('Presence initialization already in progress, skipping');
      return;
    }
    _isInitializing = true;

    try {
      // Clean up previous user if switching
      if (_currentUserId != null && _currentUserId != userId) {
        await dispose();
      }

      _currentUserId = userId;
      _userStatusRef = _rtdb.ref('status/$userId');
      _connectedRef = _rtdb.ref('.info/connected');

      // Register lifecycle observer
      WidgetsBinding.instance.addObserver(this);

      // Setup presence on connection state changes
      _connectedSubscription = _connectedRef!.onValue.listen((event) {
        final connected = event.snapshot.value as bool? ?? false;

        if (connected) {
          _setOnline();
        }
      });

      _isInitialized = true;
      _logger.i('Presence service initialized for user: $userId');
    } finally {
      _isInitializing = false;
    }
  }

  /// Set user as online and configure onDisconnect handler.
  Future<void> _setOnline() async {
    if (_userStatusRef == null) return;

    try {
      // When this client disconnects, update the status to offline
      await _userStatusRef!.onDisconnect().set({
        'state': 'offline',
        'lastSeen': ServerValue.timestamp,
      });

      // Then set the current state to online
      await _userStatusRef!.set({
        'state': 'online',
        'lastSeen': ServerValue.timestamp,
      });

      _logger.d('User set to online with onDisconnect configured');
    } catch (e) {
      _logger.e('Error setting online status', error: e);
    }
  }

  /// Set user as away (app in background).
  Future<void> _setAway() async {
    if (_userStatusRef == null) return;

    try {
      await _userStatusRef!.set({
        'state': 'away',
        'lastSeen': ServerValue.timestamp,
      });
      _logger.d('User set to away');
    } catch (e) {
      _logger.e('Error setting away status', error: e);
    }
  }

  /// Set user as offline (manual disconnect).
  Future<void> _setOffline() async {
    if (_userStatusRef == null) return;

    try {
      await _userStatusRef!.set({
        'state': 'offline',
        'lastSeen': ServerValue.timestamp,
      });
      _logger.d('User set to offline');
    } catch (e) {
      _logger.e('Error setting offline status', error: e);
    }
  }

  /// Handle app lifecycle changes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_currentUserId == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _setOnline();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _setAway();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // onDisconnect will handle this
        break;
    }
  }

  /// Start watching another user's presence.
  void watchPresence(String userId) {
    if (_presenceSubscriptions.containsKey(userId)) {
      return; // Already watching
    }

    final ref = _rtdb.ref('status/$userId');
    _presenceSubscriptions[userId] = ref.onValue.listen(
      (event) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        final presence = PresenceState.fromRtdb(data);
        _presenceCache[userId] = presence;

        // Broadcast update
        if (!_presenceController.isClosed) {
          _presenceController.add(Map.from(_presenceCache));
        }
      },
      onError: (error) {
        _logger.e('Error watching presence for $userId', error: error);
      },
    );

    _logger.d('Started watching presence for user: $userId');
  }

  /// Stop watching another user's presence.
  void unwatchPresence(String userId) {
    _presenceSubscriptions[userId]?.cancel();
    _presenceSubscriptions.remove(userId);
    _presenceCache.remove(userId);
    _logger.d('Stopped watching presence for user: $userId');
  }

  /// Get presence for a user (one-time read).
  Future<PresenceState> getPresence(String userId) async {
    // Return cached if available and fresh (within 30 seconds)
    final cached = _presenceCache[userId];
    if (cached != null) {
      return cached;
    }

    try {
      final snapshot = await _rtdb.ref('status/$userId').get();
      final data = snapshot.value as Map<dynamic, dynamic>?;
      final presence = PresenceState.fromRtdb(data);
      _presenceCache[userId] = presence;
      return presence;
    } catch (e) {
      _logger.e('Error getting presence for $userId', error: e);
      return PresenceState(
        status: PresenceStatus.offline,
        lastSeen: DateTime.now(),
      );
    }
  }

  /// Sync current user's presence to Firestore for a specific conversation.
  /// This enables chat participants to see online status.
  Future<void> syncToFirestoreConversation(String conversationId) async {
    if (_currentUserId == null) return;

    try {
      await _firestore.collection('conversations').doc(conversationId).update({
        'participantInfo.$_currentUserId.isOnline': true,
        'participantInfo.$_currentUserId.lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.e('Error syncing presence to Firestore', error: e);
    }
  }

  /// Update Firestore when going offline.
  Future<void> _syncOfflineToFirestore() async {
    if (_currentUserId == null) return;

    // Skip if user is no longer authenticated (e.g. sign-out already happened)
    if (auth.FirebaseAuth.instance.currentUser == null) return;

    // Note: This is best-effort. The RTDB onDisconnect is the source of truth.
    // Firestore sync happens when the app can still communicate.
    try {
      // Get all conversations for this user and update presence
      final conversations = await _firestore
          .collection('conversations')
          .where('participantIds', arrayContains: _currentUserId)
          .get();

      final batch = _firestore.batch();
      for (final doc in conversations.docs) {
        batch.update(doc.reference, {
          'participantInfo.$_currentUserId.isOnline': false,
          'participantInfo.$_currentUserId.lastSeen': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      _logger.e('Error syncing offline status to Firestore', error: e);
    }
  }

  /// Clean up resources.
  Future<void> dispose() async {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Set offline before disposing
    await _setOffline();
    await _syncOfflineToFirestore();

    // Cancel all subscriptions
    await _connectedSubscription?.cancel();
    for (final sub in _presenceSubscriptions.values) {
      await sub.cancel();
    }
    _presenceSubscriptions.clear();
    _presenceCache.clear();

    // Cancel onDisconnect if we're manually going offline
    await _userStatusRef?.onDisconnect().cancel();

    _currentUserId = null;
    _userStatusRef = null;
    _isInitialized = false;

    _logger.i('Presence service disposed');
  }

  /// Full cleanup including stream controller.
  Future<void> shutdown() async {
    await dispose();
    await _presenceController.close();
  }
}
