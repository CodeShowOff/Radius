import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/nearby_group_member.dart';

/// Firestore model for NearbyGroupMember entity.
///
/// Firestore structure:
/// ```
/// nearby_groups/{groupId}/members/{memberId}
///   - id: string (userId)
///   - username: string
///   - displayName: string?
///   - photoUrl: string?
///   - rssi: int
///   - joinedAt: timestamp
///   - lastSeenAt: timestamp
/// ```
class NearbyGroupMemberModel extends NearbyGroupMember {
  const NearbyGroupMemberModel({
    required super.id,
    required super.username,
    super.displayName,
    super.photoUrl,
    required super.rssi,
    required super.joinedAt,
    required super.lastSeenAt,
  });

  /// Creates a model from Firestore document snapshot.
  factory NearbyGroupMemberModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return NearbyGroupMemberModel(
      id: doc.id,
      username: data['username'] as String,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      rssi: (data['rssi'] as num?)?.toInt() ?? -100,
      joinedAt: _parseTimestamp(data['joinedAt']),
      lastSeenAt: _parseTimestamp(data['lastSeenAt']),
    );
  }

  /// Creates a model from a map (for stream data).
  factory NearbyGroupMemberModel.fromMap(Map<String, dynamic> data, String id) {
    return NearbyGroupMemberModel(
      id: id,
      username: data['username'] as String,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      rssi: (data['rssi'] as num?)?.toInt() ?? -100,
      joinedAt: _parseTimestamp(data['joinedAt']),
      lastSeenAt: _parseTimestamp(data['lastSeenAt']),
    );
  }

  /// Converts the model to Firestore data.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'userId': id,
      'username': username,
      if (displayName != null) 'displayName': displayName,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'rssi': rssi,
      'joinedAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(joinedAt),
      'lastSeenAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(lastSeenAt),
    };
  }

  /// Converts the model to an entity.
  NearbyGroupMember toEntity() {
    return NearbyGroupMember(
      id: id,
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
      rssi: rssi,
      joinedAt: joinedAt,
      lastSeenAt: lastSeenAt,
    );
  }

  /// Creates a new member model for adding to a group.
  factory NearbyGroupMemberModel.create({
    required String userId,
    required String username,
    String? displayName,
    String? photoUrl,
    required int rssi,
  }) {
    final now = DateTime.now();
    return NearbyGroupMemberModel(
      id: userId,
      username: username,
      displayName: displayName,
      photoUrl: photoUrl,
      rssi: rssi,
      joinedAt: now,
      lastSeenAt: now,
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
