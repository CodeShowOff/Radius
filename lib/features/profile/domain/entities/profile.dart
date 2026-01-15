import 'package:equatable/equatable.dart';

/// Domain entity representing a user profile.
class Profile extends Equatable {
  final String id;
  final String userId;
  final String name;
  final String bio;
  final String? photoUrl;
  final bool isVisible;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Profile({
    required this.id,
    required this.userId,
    required this.name,
    this.bio = '',
    this.photoUrl,
    this.isVisible = true,
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
        createdAt,
        updatedAt,
      ];
}
