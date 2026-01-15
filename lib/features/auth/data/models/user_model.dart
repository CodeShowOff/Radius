import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/user.dart';

/// User data transfer object for Firestore serialization.
///
/// Maps between Firestore documents and User domain entities.
class UserModel {
  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final String bleIdentifier;
  final DateTime createdAt;
  final bool isDiscoverable;

  const UserModel({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    required this.bleIdentifier,
    required this.createdAt,
    this.isDiscoverable = true,
  });

  /// Creates a UserModel from a Firestore document.
  factory UserModel.fromFirestore(Map<String, dynamic> doc) {
    return UserModel(
      id: doc['id'] as String,
      email: doc['email'] as String,
      displayName: doc['displayName'] as String?,
      avatarUrl: doc['avatarUrl'] as String?,
      bleIdentifier: doc['bleIdentifier'] as String,
      createdAt: (doc['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDiscoverable: doc['isDiscoverable'] as bool? ?? true,
    );
  }

  /// Creates a UserModel from a domain User entity.
  factory UserModel.fromEntity(User user) {
    return UserModel(
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      bleIdentifier: user.bleIdentifier,
      createdAt: user.createdAt,
      isDiscoverable: user.isDiscoverable,
    );
  }

  /// Converts this model to a Firestore document.
  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'bleIdentifier': bleIdentifier,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDiscoverable': isDiscoverable,
    };
  }

  /// Converts this model to a domain User entity.
  User toEntity() {
    return User(
      id: id,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
      bleIdentifier: bleIdentifier,
      createdAt: createdAt,
      isDiscoverable: isDiscoverable,
    );
  }

  /// Creates a copy with the given fields replaced.
  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? bleIdentifier,
    DateTime? createdAt,
    bool? isDiscoverable,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bleIdentifier: bleIdentifier ?? this.bleIdentifier,
      createdAt: createdAt ?? this.createdAt,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
    );
  }
}
