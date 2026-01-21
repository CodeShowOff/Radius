part of 'connection_bloc.dart';

/// Status of the connection bloc.
enum ConnectionBlocStatus {
  initial,
  loading,
  loaded,
  error,
}

/// Cached profile data for a user.
class CachedProfile extends Equatable {
  final String id;
  final String displayName;
  final String? photoUrl;
  final String? bio;
  final String? vibe;
  final String? mood;
  final String? gender;
  final DateTime cachedAt;

  const CachedProfile({
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.vibe,
    this.mood,
    this.gender,
    required this.cachedAt,
  });

  /// Convert to Map for UI compatibility
  Map<String, dynamic> toMap() => {
        'id': id,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'bio': bio,
        'vibe': vibe,
        'mood': mood,
        'gender': gender,
      };

  @override
  List<Object?> get props => [id, displayName, photoUrl, bio, vibe, mood, gender, cachedAt];
}

/// State for the connection bloc.
class ConnectionBlocState extends Equatable {
  /// Current status.
  final ConnectionBlocStatus status;

  /// Current user's ID.
  final String? userId;

  /// List of user's connections.
  final List<Connection> connections;

  /// List of received (pending) requests.
  final List<ConnectionRequest> receivedRequests;

  /// List of sent (pending) requests.
  final List<ConnectionRequest> sentRequests;

  /// Connection states with specific users (cached for UI).
  final Map<String, UserConnectionState> userConnectionStates;
  
  /// Cached profile data for connected users (keyed by userId).
  /// This eliminates per-tile loading on tab switches.
  final Map<String, CachedProfile> profileCache;

  /// Error message if any.
  final String? errorMessage;

  /// Whether an action is in progress.
  final bool isActionLoading;

  /// ID of the request/connection being processed.
  final String? processingId;

  const ConnectionBlocState({
    this.status = ConnectionBlocStatus.initial,
    this.userId,
    this.connections = const [],
    this.receivedRequests = const [],
    this.sentRequests = const [],
    this.userConnectionStates = const {},
    this.profileCache = const {},
    this.errorMessage,
    this.isActionLoading = false,
    this.processingId,
  });

  /// Number of pending received requests (for badge).
  int get pendingRequestCount => receivedRequests.length;

  /// Gets connection state for a specific user.
  UserConnectionState getStateForUser(String otherUserId) {
    return userConnectionStates[otherUserId] ??
        UserConnectionState.notConnected;
  }

  /// Checks if connected with a user.
  bool isConnectedWith(String userId) {
    return connections.any((c) => c.hasUser(userId));
  }

  /// Gets the connection with a specific user.
  Connection? getConnectionWith(String userId) {
    try {
      return connections.firstWhere((c) => c.hasUser(userId));
    } catch (_) {
      return null;
    }
  }

  /// Gets sent request to a specific user.
  ConnectionRequest? getSentRequestTo(String userId) {
    try {
      return sentRequests.firstWhere((r) => r.receiverId == userId);
    } catch (_) {
      return null;
    }
  }

  /// Gets received request from a specific user.
  ConnectionRequest? getReceivedRequestFrom(String userId) {
    try {
      return receivedRequests.firstWhere((r) => r.senderId == userId);
    } catch (_) {
      return null;
    }
  }

  /// Gets cached profile for a user, returns null if not cached.
  CachedProfile? getCachedProfile(String userId) => profileCache[userId];

  /// Checks if a profile is cached and still fresh (within 5 minutes).
  bool hasValidCachedProfile(String userId) {
    final cached = profileCache[userId];
    if (cached == null) return false;
    // Cache is valid for 5 minutes
    return DateTime.now().difference(cached.cachedAt).inMinutes < 5;
  }

  ConnectionBlocState copyWith({
    ConnectionBlocStatus? status,
    String? userId,
    List<Connection>? connections,
    List<ConnectionRequest>? receivedRequests,
    List<ConnectionRequest>? sentRequests,
    Map<String, UserConnectionState>? userConnectionStates,
    Map<String, CachedProfile>? profileCache,
    String? errorMessage,
    bool? isActionLoading,
    String? processingId,
  }) {
    return ConnectionBlocState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      connections: connections ?? this.connections,
      receivedRequests: receivedRequests ?? this.receivedRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      userConnectionStates: userConnectionStates ?? this.userConnectionStates,
      profileCache: profileCache ?? this.profileCache,
      errorMessage: errorMessage,
      isActionLoading: isActionLoading ?? this.isActionLoading,
      processingId: processingId,
    );
  }

  @override
  List<Object?> get props => [
        status,
        userId,
        connections,
        receivedRequests,
        sentRequests,
        userConnectionStates,
        profileCache,
        errorMessage,
        isActionLoading,
        processingId,
      ];
}
