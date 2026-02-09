import 'package:equatable/equatable.dart';

/// A user suggestion in the daily random chat pool.
class RandomChatUser extends Equatable {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String? gender;
  final String? mood;
  final String? bio;
  final int receivedRequestCount; // how many requests they've received today

  const RandomChatUser({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.gender,
    this.mood,
    this.bio,
    this.receivedRequestCount = 0,
  });

  /// Whether this user can still receive requests (limit: 10/day).
  bool get canReceiveRequests => receivedRequestCount < 10;

  /// Creates a copy with updated fields.
  RandomChatUser copyWith({
    String? userId,
    String? displayName,
    String? photoUrl,
    String? gender,
    String? mood,
    String? bio,
    int? receivedRequestCount,
  }) {
    return RandomChatUser(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      gender: gender ?? this.gender,
      mood: mood ?? this.mood,
      bio: bio ?? this.bio,
      receivedRequestCount: receivedRequestCount ?? this.receivedRequestCount,
    );
  }

  /// Convert to JSON for caching.
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'gender': gender,
      'mood': mood,
      'bio': bio,
      'receivedRequestCount': receivedRequestCount,
    };
  }

  /// Create from JSON.
  factory RandomChatUser.fromJson(Map<String, dynamic> json) {
    return RandomChatUser(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      photoUrl: json['photoUrl'] as String?,
      gender: json['gender'] as String?,
      mood: json['mood'] as String?,
      bio: json['bio'] as String?,
      receivedRequestCount: (json['receivedRequestCount'] as int?) ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        displayName,
        photoUrl,
        gender,
        mood,
        bio,
        receivedRequestCount,
      ];
}
