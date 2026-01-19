import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/profile.dart';

/// Data Transfer Object for Profile entity.
/// Handles Firestore serialization/deserialization.
class ProfileModel {
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

  const ProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.bio,
    this.photoUrl,
    required this.isVisible,
    this.showOnlineStatus = true,
    this.allowConnectionRequests = true,
    this.showLastSeen = true,
    this.vibe,
    this.mood,
    this.gender,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Creates ProfileModel from Firestore document.
  factory ProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProfileModel(
      id: doc.id,
      userId: data['userId'] as String? ?? doc.id,
      name: data['name'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      isVisible: data['isVisible'] as bool? ?? true,
      showOnlineStatus: data['showOnlineStatus'] as bool? ?? true,
      allowConnectionRequests: data['allowConnectionRequests'] as bool? ?? true,
      showLastSeen: data['showLastSeen'] as bool? ?? true,
      vibe: data['vibe'] as String?,
      mood: data['mood'] as String?,
      gender: data['gender'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Creates ProfileModel from domain entity.
  factory ProfileModel.fromEntity(Profile profile) {
    return ProfileModel(
      id: profile.id,
      userId: profile.userId,
      name: profile.name,
      bio: profile.bio,
      photoUrl: profile.photoUrl,
      isVisible: profile.isVisible,
      showOnlineStatus: profile.showOnlineStatus,
      allowConnectionRequests: profile.allowConnectionRequests,
      showLastSeen: profile.showLastSeen,
      vibe: profile.vibe,
      mood: profile.mood,
      gender: profile.gender,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
    );
  }

  /// Converts to Firestore document map.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'bio': bio,
      'photoUrl': photoUrl,
      'isVisible': isVisible,
      'showOnlineStatus': showOnlineStatus,
      'allowConnectionRequests': allowConnectionRequests,
      'showLastSeen': showLastSeen,
      'vibe': vibe,
      'mood': mood,
      'gender': gender,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Converts to domain entity.
  Profile toEntity() {
    return Profile(
      id: id,
      userId: userId,
      name: name,
      bio: bio,
      photoUrl: photoUrl,
      isVisible: isVisible,
      showOnlineStatus: showOnlineStatus,
      allowConnectionRequests: allowConnectionRequests,
      showLastSeen: showLastSeen,
      vibe: vibe,
      mood: mood,
      gender: gender,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Creates a map for partial updates (only changed fields).
  static Map<String, dynamic> toUpdateMap({
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
  }) {
    final map = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) map['name'] = name;
    if (bio != null) map['bio'] = bio;
    if (photoUrl != null) map['photoUrl'] = photoUrl;
    if (isVisible != null) map['isVisible'] = isVisible;
    if (showOnlineStatus != null) map['showOnlineStatus'] = showOnlineStatus;
    if (allowConnectionRequests != null) {
      map['allowConnectionRequests'] = allowConnectionRequests;
    }
    if (showLastSeen != null) map['showLastSeen'] = showLastSeen;
    if (vibe != null) map['vibe'] = vibe;
    if (mood != null) map['mood'] = mood;
    if (gender != null) map['gender'] = gender;

    return map;
  }
}
