import 'package:equatable/equatable.dart';

/// Domain entity representing a user profile.
class Profile extends Equatable {
  final String id;
  final String userId;
  final String name;
  final String bio;
  final String? photoUrl;
  final bool isVisible;
  final bool showOnlineStatus;
  final bool allowConnectionRequests;
  final bool showLastSeen;
  final String? vibe;
  final String? mood;
  final String? gender;
  final String? discoveryUsername;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool notifyDirectMessages;
  final bool notifyLocationGroups;
  final bool notifyNearbyGroups;
  final bool notifyRandomGroups;

  const Profile({
    required this.id,
    required this.userId,
    required this.name,
    this.bio = '',
    this.photoUrl,
    this.isVisible = true,
    this.showOnlineStatus = true,
    this.allowConnectionRequests = true,
    this.showLastSeen = true,
    this.vibe,
    this.mood,
    this.gender,
    this.discoveryUsername,
    required this.createdAt,
    required this.updatedAt,
    this.notifyDirectMessages = true,
    this.notifyLocationGroups = true,
    this.notifyNearbyGroups = true,
    this.notifyRandomGroups = true,
  });

  /// Creates a new profile with default values.
  factory Profile.empty(String userId) {
    final now = DateTime.now();
    return Profile(
      id: userId,
      userId: userId,
      name: '',
      bio: '',
      photoUrl: null,
      isVisible: true,
      showOnlineStatus: true,
      allowConnectionRequests: true,
      showLastSeen: true,
      vibe: null,
      mood: null,
      gender: null,
      discoveryUsername: null,
      createdAt: now,
      updatedAt: now,
      notifyDirectMessages: true,
      notifyLocationGroups: true,
      notifyNearbyGroups: true,
      notifyRandomGroups: true,
    );
  }

  /// Creates a copy with updated fields.
  Profile copyWith({
    String? id,
    String? userId,
    String? name,
    String? bio,
    String? photoUrl,
    bool? isVisible,
    bool? showOnlineStatus,
    bool? allowConnectionRequests,
    bool? showLastSeen,
    String? vibe,
    String? mood,
    String? gender,
    String? discoveryUsername,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? notifyDirectMessages,
    bool? notifyLocationGroups,
    bool? notifyNearbyGroups,
    bool? notifyRandomGroups,
  }) {
    return Profile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      photoUrl: photoUrl ?? this.photoUrl,
      isVisible: isVisible ?? this.isVisible,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      allowConnectionRequests:
          allowConnectionRequests ?? this.allowConnectionRequests,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      vibe: vibe ?? this.vibe,
      mood: mood ?? this.mood,
      gender: gender ?? this.gender,
      discoveryUsername: discoveryUsername ?? this.discoveryUsername,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notifyDirectMessages: notifyDirectMessages ?? this.notifyDirectMessages,
      notifyLocationGroups: notifyLocationGroups ?? this.notifyLocationGroups,
      notifyNearbyGroups: notifyNearbyGroups ?? this.notifyNearbyGroups,
      notifyRandomGroups: notifyRandomGroups ?? this.notifyRandomGroups,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        name,
        bio,
        photoUrl,
        isVisible,
        showOnlineStatus,
        allowConnectionRequests,
        showLastSeen,
        vibe,
        mood,
        gender,
        discoveryUsername,
        createdAt,
        updatedAt,
        notifyDirectMessages,
        notifyLocationGroups,
        notifyNearbyGroups,
        notifyRandomGroups,
      ];
}
