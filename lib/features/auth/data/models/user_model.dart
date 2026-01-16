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
  final DateTime? createdAt;
  final bool isDiscoverable;

  const UserModel({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    required this.bleIdentifier,
    this.createdAt,
    this.isDiscoverable = true,
  });

  /// Creates a UserModel from a Firestore document.
  ///
  /// The [doc] map should include an 'id' field that is typically added
  /// by the FirestoreService when fetching documents. If 'id' is missing,
  /// this will throw an [ArgumentError].
  factory UserModel.fromFirestore(Map<String, dynamic> doc) {
    final id = doc['id'];
    if (id == null || id is! String || id.isEmpty) {
      throw ArgumentError('Firestore document must include a valid "id" field');
    }

    final email = doc['email'];
    if (email == null || email is! String) {
      throw ArgumentError(
          'Firestore document must include a valid "email" field');
    }

    final bleIdentifier = doc['bleIdentifier'];
    if (bleIdentifier == null || bleIdentifier is! String) {
      throw ArgumentError(
          'Firestore document must include a valid "bleIdentifier" field');
    }

    return UserModel(
      id: id,
      email: email,
      displayName: doc['displayName'] as String?,
      avatarUrl: doc['avatarUrl'] as String?,
      bleIdentifier: bleIdentifier,
      createdAt: (doc['createdAt'] as Timestamp?)?.toDate(),
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
  /// When [useServerTimestamp] is true, createdAt will use FieldValue.serverTimestamp()
  /// which is required by Firestore security rules for document creation.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'email': email,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'bleIdentifier': bleIdentifier,
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : (createdAt != null ? Timestamp.fromDate(createdAt!) : null),
      'isDiscoverable': isDiscoverable,
    };
  }

  /// Converts this model to a domain User entity.
  ///
  /// If [createdAt] is null, uses the current time as a fallback.
  /// This should only happen for newly created users before the server
  /// timestamp is resolved.
  User toEntity() {
    return User(
      id: id,
      email: email,
      displayName: displayName,
      avatarUrl: avatarUrl,
      bleIdentifier: bleIdentifier,
      createdAt: createdAt ?? DateTime.now(),
      isDiscoverable: isDiscoverable,
    );
  }

  /// Creates a copy with the given fields replaced.
  ///
  /// To explicitly set [displayName] or [avatarUrl] to null, use the
  /// [clearDisplayName] or [clearAvatarUrl] parameters.
  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? avatarUrl,
    String? bleIdentifier,
    DateTime? createdAt,
    bool? isDiscoverable,
    bool clearDisplayName = false,
    bool clearAvatarUrl = false,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: clearDisplayName ? null : (displayName ?? this.displayName),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      bleIdentifier: bleIdentifier ?? this.bleIdentifier,
      createdAt: createdAt ?? this.createdAt,
      isDiscoverable: isDiscoverable ?? this.isDiscoverable,
    );
  }
}
