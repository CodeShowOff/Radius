import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/random_group.dart';

/// Firestore model for RandomGroup entity.
///
/// Firestore structure:
/// ```
/// random_groups/{groupId}
///   - id: string
///   - name: string
///   - topic: string?
///   - description: string?
///   - creatorId: string
///   - creatorUsername: string
///   - creatorDisplayName: string?
///   - creatorPhotoUrl: string?
///   - adminIds: string[]
///   - status: string ('active' | 'inactive')
///   - memberCount: int
///   - pendingRequestCount: int
///   - createdAt: timestamp
///   - lastActiveAt: timestamp
///   - lastMessagePreview: string?
///   - lastMessageAt: timestamp?
/// ```
class RandomGroupModel extends RandomGroup {
  const RandomGroupModel({
    required super.id,
    required super.name,
    super.topic,
    super.description,
    required super.creatorId,
    required super.creatorUsername,
    super.creatorDisplayName,
    super.creatorPhotoUrl,
    required super.adminIds,
    required super.status,
    required super.memberCount,
    super.pendingRequestCount,
    required super.createdAt,
    required super.lastActiveAt,
    super.lastMessagePreview,
    super.lastMessageAt,
  });

  /// Creates a model from Firestore document snapshot.
  factory RandomGroupModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RandomGroupModel(
      id: doc.id,
      name: data['name'] as String,
      topic: data['topic'] as String?,
      description: data['description'] as String?,
      creatorId: data['creatorId'] as String,
      creatorUsername: data['creatorUsername'] as String,
      creatorDisplayName: data['creatorDisplayName'] as String?,
      creatorPhotoUrl: data['creatorPhotoUrl'] as String?,
      adminIds: List<String>.from(data['adminIds'] ?? [data['creatorId']]),
      status: _statusFromString(data['status'] as String?),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
      pendingRequestCount: (data['pendingRequestCount'] as num?)?.toInt() ?? 0,
      createdAt: _parseTimestamp(data['createdAt']),
      lastActiveAt: _parseTimestamp(data['lastActiveAt']),
      lastMessagePreview: data['lastMessagePreview'] as String?,
      lastMessageAt: data['lastMessageAt'] != null
          ? _parseTimestamp(data['lastMessageAt'])
          : null,
    );
  }

  /// Creates a model from a map (for stream data).
  factory RandomGroupModel.fromMap(Map<String, dynamic> data, String id) {
    return RandomGroupModel(
      id: id,
      name: data['name'] as String,
      topic: data['topic'] as String?,
      description: data['description'] as String?,
      creatorId: data['creatorId'] as String,
      creatorUsername: data['creatorUsername'] as String,
      creatorDisplayName: data['creatorDisplayName'] as String?,
      creatorPhotoUrl: data['creatorPhotoUrl'] as String?,
      adminIds: List<String>.from(data['adminIds'] ?? [data['creatorId']]),
      status: _statusFromString(data['status'] as String?),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 1,
      pendingRequestCount: (data['pendingRequestCount'] as num?)?.toInt() ?? 0,
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
      if (topic != null) 'topic': topic,
      if (description != null) 'description': description,
      'creatorId': creatorId,
      'creatorUsername': creatorUsername,
      if (creatorDisplayName != null) 'creatorDisplayName': creatorDisplayName,
      if (creatorPhotoUrl != null) 'creatorPhotoUrl': creatorPhotoUrl,
      'adminIds': adminIds,
      'status': _statusToString(status),
      'memberCount': memberCount,
      'pendingRequestCount': pendingRequestCount,
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt),
      'lastActiveAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(lastActiveAt),
      if (lastMessagePreview != null) 'lastMessagePreview': lastMessagePreview,
      if (lastMessageAt != null)
        'lastMessageAt': Timestamp.fromDate(lastMessageAt!),
    };
  }

  /// Converts the model to an entity.
  RandomGroup toEntity() {
    return RandomGroup(
      id: id,
      name: name,
      topic: topic,
      description: description,
      creatorId: creatorId,
      creatorUsername: creatorUsername,
      creatorDisplayName: creatorDisplayName,
      creatorPhotoUrl: creatorPhotoUrl,
      adminIds: adminIds,
      status: status,
      memberCount: memberCount,
      pendingRequestCount: pendingRequestCount,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt,
      lastMessagePreview: lastMessagePreview,
      lastMessageAt: lastMessageAt,
    );
  }

  /// Creates a new group model for creation.
  factory RandomGroupModel.create({
    required String id,
    required String name,
    String? topic,
    String? description,
    required String creatorId,
    required String creatorUsername,
    String? creatorDisplayName,
    String? creatorPhotoUrl,
  }) {
    final now = DateTime.now();
    return RandomGroupModel(
      id: id,
      name: name,
      topic: topic,
      description: description,
      creatorId: creatorId,
      creatorUsername: creatorUsername,
      creatorDisplayName: creatorDisplayName,
      creatorPhotoUrl: creatorPhotoUrl,
      adminIds: [creatorId],
      status: RandomGroupStatus.active,
      memberCount: 1,
      pendingRequestCount: 0,
      createdAt: now,
      lastActiveAt: now,
    );
  }

  static RandomGroupStatus _statusFromString(String? status) {
    switch (status) {
      case 'active':
        return RandomGroupStatus.active;
      case 'inactive':
        return RandomGroupStatus.inactive;
      default:
        return RandomGroupStatus.active;
    }
  }

  static String _statusToString(RandomGroupStatus status) {
    switch (status) {
      case RandomGroupStatus.active:
        return 'active';
      case RandomGroupStatus.inactive:
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
