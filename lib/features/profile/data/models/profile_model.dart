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
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.bio,
    this.photoUrl,
    required this.isVisible,
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
  }) {
    final map = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) map['name'] = name;
    if (bio != null) map['bio'] = bio;
    if (photoUrl != null) map['photoUrl'] = photoUrl;
    if (isVisible != null) map['isVisible'] = isVisible;

    return map;
  }
}
