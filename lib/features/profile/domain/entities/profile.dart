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
  final DateTime createdAt;
  final DateTime updatedAt;

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
    required this.createdAt,
    required this.updatedAt,
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
      createdAt: now,
      updatedAt: now,
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
    DateTime? createdAt,
    DateTime? updatedAt,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
        createdAt,
        updatedAt,
      ];
}
