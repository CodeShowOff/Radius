import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/location_group.dart';

/// Firestore model for LocationGroup entity.
///
/// Firestore Schema:
/// ```
/// location_groups/{groupId}
///   - name: string
///   - description: string?
///   - countryCode: string
///   - stateCode: string
///   - countryName: string
///   - stateName: string
///   - createdByUserId: string
///   - createdByUserName: string?
///   - visibility: string ('public' | 'requestToJoin')
///   - status: string ('active' | 'archived')
///   - memberCount: number
///   - createdAt: timestamp
///   - lastActivityAt: timestamp?
///   - lastMessagePreview: string?
///   - avatarUrl: string?
/// ```
class LocationGroupModel extends LocationGroup {
  const LocationGroupModel({
    required super.id,
    required super.name,
    super.description,
    required super.countryCode,
    required super.stateCode,
    required super.countryName,
    required super.stateName,
    required super.createdByUserId,
    super.createdByUserName,
    required super.visibility,
    required super.status,
    required super.memberCount,
    required super.createdAt,
    super.lastActivityAt,
    super.lastMessagePreview,
    super.avatarUrl,
  });

  /// Creates model from Firestore document.
  factory LocationGroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return LocationGroupModel(
      id: doc.id,
      name: data['name'] as String,
      description: data['description'] as String?,
      countryCode: data['countryCode'] as String,
      stateCode: data['stateCode'] as String,
      countryName: data['countryName'] as String,
      stateName: data['stateName'] as String,
      createdByUserId: data['createdByUserId'] as String,
      createdByUserName: data['createdByUserName'] as String?,
      visibility: _parseVisibility(data['visibility'] as String?),
      status: _parseStatus(data['status'] as String?),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActivityAt: (data['lastActivityAt'] as Timestamp?)?.toDate(),
      lastMessagePreview: data['lastMessagePreview'] as String?,
      avatarUrl: data['avatarUrl'] as String?,
    );
  }

  /// Creates model from LocationGroup entity.
  factory LocationGroupModel.fromEntity(LocationGroup group) {
    return LocationGroupModel(
      id: group.id,
      name: group.name,
      description: group.description,
      countryCode: group.countryCode,
      stateCode: group.stateCode,
      countryName: group.countryName,
      stateName: group.stateName,
      createdByUserId: group.createdByUserId,
      createdByUserName: group.createdByUserName,
      visibility: group.visibility,
      status: group.status,
      memberCount: group.memberCount,
      createdAt: group.createdAt,
      lastActivityAt: group.lastActivityAt,
      lastMessagePreview: group.lastMessagePreview,
      avatarUrl: group.avatarUrl,
    );
  }

  /// Converts model to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'countryCode': countryCode,
      'stateCode': stateCode,
      'countryName': countryName,
      'stateName': stateName,
      'createdByUserId': createdByUserId,
      'createdByUserName': createdByUserName,
      'visibility': visibility.name,
      'status': status.name,
      'memberCount': memberCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActivityAt':
          lastActivityAt != null ? Timestamp.fromDate(lastActivityAt!) : null,
      'lastMessagePreview': lastMessagePreview,
      'avatarUrl': avatarUrl,
      // Search fields for queries
      'nameLowercase': name.toLowerCase(),
      'searchKey': '${countryCode}_$stateCode'.toLowerCase(),
    };
  }

  /// Converts to data for creating a new group (uses server timestamp).
  Map<String, dynamic> toCreateData() {
    return {
      'name': name,
      'description': description,
      'countryCode': countryCode,
      'stateCode': stateCode,
      'countryName': countryName,
      'stateName': stateName,
      'createdByUserId': createdByUserId,
      'createdByUserName': createdByUserName,
      'visibility': visibility.name,
      'status': status.name,
      'memberCount': 1, // Creator is first member
      'createdAt': FieldValue.serverTimestamp(),
      'lastActivityAt': FieldValue.serverTimestamp(),
      'lastMessagePreview': null,
      'avatarUrl': avatarUrl,
      'nameLowercase': name.toLowerCase(),
      'searchKey': '${countryCode}_$stateCode'.toLowerCase(),
    };
  }

  static GroupVisibility _parseVisibility(String? value) {
    switch (value) {
      case 'requestToJoin':
        return GroupVisibility.requestToJoin;
      case 'public':
      default:
        return GroupVisibility.public;
    }
  }

  static GroupStatus _parseStatus(String? value) {
    switch (value) {
      case 'archived':
        return GroupStatus.archived;
      case 'active':
      default:
        return GroupStatus.active;
    }
  }
}
