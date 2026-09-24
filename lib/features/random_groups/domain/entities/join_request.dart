import 'package:equatable/equatable.dart';

/// Status of a join request.
enum JoinRequestStatus {
  /// Request is pending admin approval
  pending,

  /// Request was approved
  approved,

  /// Request was rejected
  rejected,
}

/// Represents a request to join a random group.
class JoinRequest extends Equatable {
  /// Unique identifier for the request
  final String id;

  /// Group ID being requested
  final String groupId;

  /// User ID of the requester
  final String requesterId;

  /// Requester's username
  final String requesterUsername;

  /// Requester's display name
  final String? requesterDisplayName;

  /// Requester's photo URL
  final String? requesterPhotoUrl;

  /// Optional message from the requester
  final String? message;

  /// Status of the request
  final JoinRequestStatus status;

  /// When the request was created
  final DateTime requestedAt;

  /// When the request was handled (approved/rejected)
  final DateTime? handledAt;

  /// User ID of the admin who handled the request
  final String? handledBy;

  const JoinRequest({
    required this.id,
    required this.groupId,
    required this.requesterId,
    required this.requesterUsername,
    this.requesterDisplayName,
    this.requesterPhotoUrl,
    this.message,
    required this.status,
    required this.requestedAt,
    this.handledAt,
    this.handledBy,
  });

  /// Helper to check if request is pending
  bool get isPending => status == JoinRequestStatus.pending;

  /// Creates a copy with updated fields
  JoinRequest copyWith({
    String? id,
    String? groupId,
    String? requesterId,
    String? requesterUsername,
    String? requesterDisplayName,
    String? requesterPhotoUrl,
    String? message,
    JoinRequestStatus? status,
    DateTime? requestedAt,
    DateTime? handledAt,
    String? handledBy,
  }) {
    return JoinRequest(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      requesterId: requesterId ?? this.requesterId,
      requesterUsername: requesterUsername ?? this.requesterUsername,
      requesterDisplayName: requesterDisplayName ?? this.requesterDisplayName,
      requesterPhotoUrl: requesterPhotoUrl ?? this.requesterPhotoUrl,
      message: message ?? this.message,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      handledAt: handledAt ?? this.handledAt,
      handledBy: handledBy ?? this.handledBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        requesterId,
        requesterUsername,
        requesterDisplayName,
        requesterPhotoUrl,
        message,
        status,
        requestedAt,
        handledAt,
        handledBy,
      ];
}
