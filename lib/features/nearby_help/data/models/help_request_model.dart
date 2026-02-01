import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/help_radius.dart';
import '../../domain/entities/help_request.dart';
import '../../domain/entities/help_request_status.dart';

/// Firestore model for HelpRequest entity.
///
/// Firestore Schema:
/// ```
/// help_requests/{requestId}
///   - seekerUserId: string
///   - seekerName: string
///   - seekerPhotoUrl: string?
///   - helperUserId: string?
///   - helperName: string?
///   - helperPhotoUrl: string?
///   - latitude: number
///   - longitude: number
///   - radius: number (meters)
///   - topic: string?
///   - status: string ('OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CANCELLED' | 'EXPIRED')
///   - createdAt: timestamp
///   - assignedAt: timestamp?
///   - resolvedAt: timestamp?
///   - expiresAt: timestamp
///   - helperOnTheWay: boolean
///   - updatedAt: timestamp
///   - geoHash: string (for geospatial queries)
/// ```
class HelpRequestModel extends HelpRequest {
  /// GeoHash for efficient geospatial queries.
  final String? geoHash;

  const HelpRequestModel({
    required super.id,
    required super.seekerUserId,
    required super.seekerName,
    super.seekerPhotoUrl,
    super.helperUserId,
    super.helperName,
    super.helperPhotoUrl,
    required super.latitude,
    required super.longitude,
    required super.radius,
    super.topic,
    required super.status,
    required super.createdAt,
    super.assignedAt,
    super.resolvedAt,
    required super.expiresAt,
    super.helperOnTheWay = false,
    required super.updatedAt,
    this.geoHash,
  });

  /// Creates model from Firestore document.
  factory HelpRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return HelpRequestModel(
      id: doc.id,
      seekerUserId: data['seekerUserId'] as String,
      seekerName: data['seekerName'] as String? ?? 'Unknown',
      seekerPhotoUrl: data['seekerPhotoUrl'] as String?,
      helperUserId: data['helperUserId'] as String?,
      helperName: data['helperName'] as String?,
      helperPhotoUrl: data['helperPhotoUrl'] as String?,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      radius: HelpRadius.fromMeters((data['radius'] as num?)?.toInt() ?? 50),
      topic: data['topic'] as String?,
      status: HelpRequestStatusX.fromString(data['status'] as String? ?? 'OPEN'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      assignedAt: (data['assignedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(minutes: 30)),
      helperOnTheWay: data['helperOnTheWay'] as bool? ?? false,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      geoHash: data['geoHash'] as String?,
    );
  }

  /// Creates model from HelpRequest entity.
  factory HelpRequestModel.fromEntity(HelpRequest request, {String? geoHash}) {
    return HelpRequestModel(
      id: request.id,
      seekerUserId: request.seekerUserId,
      seekerName: request.seekerName,
      seekerPhotoUrl: request.seekerPhotoUrl,
      helperUserId: request.helperUserId,
      helperName: request.helperName,
      helperPhotoUrl: request.helperPhotoUrl,
      latitude: request.latitude,
      longitude: request.longitude,
      radius: request.radius,
      topic: request.topic,
      status: request.status,
      createdAt: request.createdAt,
      assignedAt: request.assignedAt,
      resolvedAt: request.resolvedAt,
      expiresAt: request.expiresAt,
      helperOnTheWay: request.helperOnTheWay,
      updatedAt: request.updatedAt,
      geoHash: geoHash,
    );
  }

  /// Converts model to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'seekerUserId': seekerUserId,
      'seekerName': seekerName,
      'seekerPhotoUrl': seekerPhotoUrl,
      'helperUserId': helperUserId,
      'helperName': helperName,
      'helperPhotoUrl': helperPhotoUrl,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius.meters,
      'topic': topic,
      'status': status.value,
      'createdAt': Timestamp.fromDate(createdAt),
      'assignedAt': assignedAt != null ? Timestamp.fromDate(assignedAt!) : null,
      'resolvedAt': resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'helperOnTheWay': helperOnTheWay,
      'updatedAt': FieldValue.serverTimestamp(),
      'geoHash': geoHash,
    };
  }

  /// Converts model to Firestore document data for creation (without null fields).
  Map<String, dynamic> toFirestoreCreate() {
    final data = <String, dynamic>{
      'seekerUserId': seekerUserId,
      'seekerName': seekerName,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius.meters,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'helperOnTheWay': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (seekerPhotoUrl != null) data['seekerPhotoUrl'] = seekerPhotoUrl;
    if (topic != null && topic!.isNotEmpty) data['topic'] = topic;
    if (geoHash != null) data['geoHash'] = geoHash;

    return data;
  }
}
