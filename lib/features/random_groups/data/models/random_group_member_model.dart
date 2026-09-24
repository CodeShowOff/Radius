import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/random_group_member.dart';

/// Firestore model for RandomGroupMember entity.
///
/// Firestore structure:
/// ```
/// random_groups/{groupId}/members/{memberId}
///   - id: string (userId)
///   - username: string
///   - displayName: string?
///   - photoUrl: string?
///   - joinedAt: timestamp
///   - isAdmin: bool
/// ```
class RandomGroupMemberModel extends RandomGroupMember {
  const RandomGroupMemberModel({
    required super.id,
    required super.username,
    super.displayName,
    super.photoUrl,
    required super.joinedAt,
    super.isAdmin,
  });

  /// Creates a model from Firestore document snapshot.
  factory RandomGroupMemberModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RandomGroupMemberModel(
      id: doc.id,
      username: data['username'] as String,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      joinedAt: _parseTimestamp(data['joinedAt']),
      isAdmin: data['isAdmin'] as bool? ?? false,
    );
  }

  /// Creates a model from a map (for stream data).
  factory RandomGroupMemberModel.fromMap(Map<String, dynamic> data, String id) {
    return RandomGroupMemberModel(
      id: id,
      username: data['username'] as String,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      joinedAt: _parseTimestamp(data['joinedAt']),
      isAdmin: data['isAdmin'] as bool? ?? false,
    );
  }

  /// Converts the model to Firestore data.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'userId': id,
      'username': username,
      if (displayName != null) 'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'joinedAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(joinedAt),
      'isAdmin': isAdmin,
    };
  }

  /// Converts the model to an entity.
  RandomGroupMember toEntity() {
    return RandomGroupMember(
      id: id,
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
      joinedAt: joinedAt,
      isAdmin: isAdmin,
    );
  }

  /// Creates a new member model for adding to a group.
  factory RandomGroupMemberModel.create({
    required String userId,
    required String username,
    String? displayName,
    String? photoUrl,
    bool isAdmin = false,
  }) {
    return RandomGroupMemberModel(
      id: userId,
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
      joinedAt: DateTime.now(),
      isAdmin: isAdmin,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    } else if (value is DateTime) {
      return value;
    } else {
      return DateTime.now();
    }
  }
}
