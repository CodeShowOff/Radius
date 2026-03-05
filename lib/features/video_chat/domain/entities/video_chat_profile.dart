import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// An anonymous profile used exclusively in Random Video Chat.
///
/// Completely separate from the user's real Radius profile.
/// Stored in Firestore under `video_chat_profiles/{userId}`.
/// Users set this up the first time and can modify it each session.
class VideoChatProfile extends Equatable {
  /// The user's Firebase Auth UID (internal only — never shown to match).
  final String userId;

  /// Display name chosen by the user for video chat.
  final String displayName;

  /// Optional profile photo URL (uploaded to Firebase Storage).
  final String? photoUrl;

  /// Timestamp when the profile was first created.
  final DateTime createdAt;

  /// Timestamp when the profile was last updated.
  final DateTime updatedAt;

  const VideoChatProfile({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Whether the profile has been fully set up (has a display name).
  bool get isComplete => displayName.trim().isNotEmpty;

  VideoChatProfile copyWith({
    String? userId,
    String? displayName,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearPhotoUrl = false,
  }) {
    return VideoChatProfile(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory VideoChatProfile.fromJson(Map<String, dynamic> json) {
    return VideoChatProfile(
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(json['updatedAt']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  List<Object?> get props => [userId, displayName, photoUrl, createdAt, updatedAt];
}
