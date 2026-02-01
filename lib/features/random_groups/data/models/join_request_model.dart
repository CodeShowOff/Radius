import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/join_request.dart';

/// Firestore model for JoinRequest entity.
///
/// Firestore structure:
/// ```
/// random_groups/{groupId}/join_requests/{requestId}
///   - id: string
///   - groupId: string
///   - requesterId: string
///   - requesterUsername: string
///   - requesterDisplayName: string?
///   - requesterPhotoUrl: string?
///   - message: string?
///   - status: string ('pending' | 'approved' | 'rejected')
///   - requestedAt: timestamp
///   - handledAt: timestamp?
///   - handledBy: string?
/// ```
class JoinRequestModel extends JoinRequest {
  const JoinRequestModel({
    required super.id,
    required super.groupId,
    required super.requesterId,
    required super.requesterUsername,
    super.requesterDisplayName,
    super.requesterPhotoUrl,
    super.message,
    required super.status,
    required super.requestedAt,
    super.handledAt,
    super.handledBy,
  });

  /// Creates a model from Firestore document snapshot.
  factory JoinRequestModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return JoinRequestModel(
      id: doc.id,
      groupId: data['groupId'] as String,
      requesterId: data['requesterId'] as String,
      requesterUsername: data['requesterUsername'] as String,
      requesterDisplayName: data['requesterDisplayName'] as String?,
      requesterPhotoUrl: data['requesterPhotoUrl'] as String?,
      message: data['message'] as String?,
      status: _statusFromString(data['status'] as String?),
      requestedAt: _parseTimestamp(data['requestedAt']),
      handledAt: data['handledAt'] != null
          ? _parseTimestamp(data['handledAt'])
          : null,
      handledBy: data['handledBy'] as String?,
    );
  }

  /// Creates a model from a map (for stream data).
  factory JoinRequestModel.fromMap(Map<String, dynamic> data, String id) {
    return JoinRequestModel(
      id: id,
      groupId: data['groupId'] as String,
      requesterId: data['requesterId'] as String,
      requesterUsername: data['requesterUsername'] as String,
      requesterDisplayName: data['requesterDisplayName'] as String?,
      requesterPhotoUrl: data['requesterPhotoUrl'] as String?,
      message: data['message'] as String?,
      status: _statusFromString(data['status'] as String?),
      requestedAt: _parseTimestamp(data['requestedAt']),
      handledAt: data['handledAt'] != null
          ? _parseTimestamp(data['handledAt'])
          : null,
      handledBy: data['handledBy'] as String?,
    );
  }

  /// Converts the model to Firestore data.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'groupId': groupId,
      'requesterId': requesterId,
      'requesterUsername': requesterUsername,
      if (requesterDisplayName != null)
        'requesterDisplayName': requesterDisplayName,
      if (requesterPhotoUrl != null) 'requesterPhotoUrl': requesterPhotoUrl,
      if (message != null) 'message': message,
      'status': _statusToString(status),
      'requestedAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(requestedAt),
      if (handledAt != null) 'handledAt': Timestamp.fromDate(handledAt!),
      if (handledBy != null) 'handledBy': handledBy,
    };
  }

  /// Converts the model to an entity.
  JoinRequest toEntity() {
    return JoinRequest(
      id: id,
      groupId: groupId,
      requesterId: requesterId,
      requesterUsername: requesterUsername,
      requesterDisplayName: requesterDisplayName,
      requesterPhotoUrl: requesterPhotoUrl,
      message: message,
      status: status,
      requestedAt: requestedAt,
      handledAt: handledAt,
      handledBy: handledBy,
    );
  }

  /// Creates a new join request model.
  factory JoinRequestModel.create({
    required String id,
    required String groupId,
    required String requesterId,
    required String requesterUsername,
    String? requesterDisplayName,
    String? requesterPhotoUrl,
    String? message,
  }) {
    return JoinRequestModel(
      id: id,
      groupId: groupId,
      requesterId: requesterId,
      requesterUsername: requesterUsername,
      requesterDisplayName: requesterDisplayName,
      requesterPhotoUrl: requesterPhotoUrl,
      message: message,
      status: JoinRequestStatus.pending,
      requestedAt: DateTime.now(),
    );
  }

  static JoinRequestStatus _statusFromString(String? status) {
    switch (status) {
      case 'pending':
        return JoinRequestStatus.pending;
      case 'approved':
        return JoinRequestStatus.approved;
      case 'rejected':
        return JoinRequestStatus.rejected;
      default:
        return JoinRequestStatus.pending;
    }
  }

  static String _statusToString(JoinRequestStatus status) {
    switch (status) {
      case JoinRequestStatus.pending:
        return 'pending';
      case JoinRequestStatus.approved:
        return 'approved';
      case JoinRequestStatus.rejected:
        return 'rejected';
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
