import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/nearby_group.dart';

/// Firestore model for NearbyGroup entity.
///
/// Firestore structure:
/// ```
/// nearby_groups/{groupId}
///   - id: string
///   - name: string
///   - description: string?
///   - creatorId: string
///   - creatorUsername: string
///   - creatorDisplayName: string?
///   - creatorPhotoUrl: string?
///   - status: string ('active' | 'inactive')
///   - memberCount: int
///   - createdAt: timestamp
///   - lastActiveAt: timestamp
///   - lastMessagePreview: string?
///   - lastMessageAt: timestamp?
/// ```
class NearbyGroupModel extends NearbyGroup {
  const NearbyGroupModel({
    required super.id,
    required super.name,
    super.description,
    required super.creatorId,
    required super.creatorUsername,
    super.creatorDisplayName,
    super.creatorPhotoUrl,
    required super.status,
    required super.memberCount,
    required super.createdAt,
    required super.lastActiveAt,
    super.lastMessagePreview,
    super.lastMessageAt,
  });

  /// Creates a model from Firestore document snapshot.
  factory NearbyGroupModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return NearbyGroupModel(
      id: doc.id,
      name: data['name'] as String,
      description: data['description'] as String?,
      creatorId: data['creatorId'] as String,
      creatorUsername: data['creatorUsername'] as String,
      creatorDisplayName: data['creatorDisplayName'] as String?,
      creatorPhotoUrl: data['creatorPhotoUrl'] as String?,
      status: _statusFromString(data['status'] as String?),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
      createdAt: _parseTimestamp(data['createdAt']),
      lastActiveAt: _parseTimestamp(data['lastActiveAt']),
      lastMessagePreview: data['lastMessagePreview'] as String?,
      lastMessageAt: data['lastMessageAt'] != null
          ? _parseTimestamp(data['lastMessageAt'])
          : null,
    );
  }

  /// Creates a model from a map (for stream data).
  factory NearbyGroupModel.fromMap(Map<String, dynamic> data, String id) {
    return NearbyGroupModel(
      id: id,
      name: data['name'] as String,
      description: data['description'] as String?,
      creatorId: data['creatorId'] as String,
      creatorUsername: data['creatorUsername'] as String,
      creatorDisplayName: data['creatorDisplayName'] as String?,
      creatorPhotoUrl: data['creatorPhotoUrl'] as String?,
      status: _statusFromString(data['status'] as String?),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
      createdAt: _parseTimestamp(data['createdAt']),
      lastActiveAt: _parseTimestamp(data['lastActiveAt']),
      lastMessagePreview: data['lastMessagePreview'] as String?,
      lastMessageAt: data['lastMessageAt'] != null
          ? _parseTimestamp(data['lastMessageAt'])
          : null,
    );
  }

  /// Converts the model to Firestore data.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'name': name,
      if (description != null) 'description': description,
      'creatorId': creatorId,
      'creatorUsername': creatorUsername,
      if (creatorDisplayName != null) 'creatorDisplayName': creatorDisplayName,
      if (creatorPhotoUrl != null) 'creatorPhotoUrl': creatorPhotoUrl,
      'status': _statusToString(status),
      'memberCount': memberCount,
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt),
      'lastActiveAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(lastActiveAt),
      if (lastMessagePreview != null) 'lastMessagePreview': lastMessagePreview,
      if (lastMessageAt != null) 'lastMessageAt': Timestamp.fromDate(lastMessageAt!),
    };
  }

  /// Converts the model to an entity.
  NearbyGroup toEntity() {
    return NearbyGroup(
      id: id,
      name: name,
      description: description,
      creatorId: creatorId,
      creatorUsername: creatorUsername,
      creatorDisplayName: creatorDisplayName,
      creatorPhotoUrl: creatorPhotoUrl,
      status: status,
      memberCount: memberCount,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt,
      lastMessagePreview: lastMessagePreview,
      lastMessageAt: lastMessageAt,
    );
  }

  /// Creates a new group model for creation.
  factory NearbyGroupModel.create({
    required String id,
    required String name,
    String? description,
    required String creatorId,
    required String creatorUsername,
    String? creatorDisplayName,
    String? creatorPhotoUrl,
  }) {
    final now = DateTime.now();
    return NearbyGroupModel(
      id: id,
      name: name,
      description: description,
      creatorId: creatorId,
      creatorUsername: creatorUsername,
      creatorDisplayName: creatorDisplayName,
      creatorPhotoUrl: creatorPhotoUrl,
      status: NearbyGroupStatus.active,
      memberCount: 1,
      createdAt: now,
      lastActiveAt: now,
    );
  }

  static NearbyGroupStatus _statusFromString(String? status) {
    switch (status) {
      case 'active':
        return NearbyGroupStatus.active;
      case 'inactive':
        return NearbyGroupStatus.inactive;
      default:
        return NearbyGroupStatus.inactive;
    }
  }

  static String _statusToString(NearbyGroupStatus status) {
    switch (status) {
      case NearbyGroupStatus.active:
        return 'active';
      case NearbyGroupStatus.inactive:
        return 'inactive';
    }
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
