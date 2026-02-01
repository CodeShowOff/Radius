import 'package:equatable/equatable.dart';

import 'help_radius.dart';
import 'help_request_status.dart';

/// Domain entity representing a help request.
///
/// A seeker creates a help request with their location and radius.
/// Nearby helpers are notified and can accept the request.
/// Only one helper can be assigned at a time (atomic locking).
class HelpRequest extends Equatable {
  /// Unique identifier for the request.
  final String id;

  /// User ID of the person seeking help.
  final String seekerUserId;

  /// Display name of the seeker.
  final String seekerName;

  /// Photo URL of the seeker (optional).
  final String? seekerPhotoUrl;

  /// User ID of the assigned helper (null until someone accepts).
  final String? helperUserId;

  /// Display name of the assigned helper.
  final String? helperName;

  /// Photo URL of the assigned helper.
  final String? helperPhotoUrl;

  /// Seeker's latitude at time of request.
  final double latitude;

  /// Seeker's longitude at time of request.
  final double longitude;

  /// Help discovery radius.
  final HelpRadius radius;

  /// Optional topic/description of the help needed.
  final String? topic;

  /// Current status of the request.
  final HelpRequestStatus status;

  /// When the request was created.
  final DateTime createdAt;

  /// When a helper was assigned (null if still open).
  final DateTime? assignedAt;

  /// When the help was completed (null if not resolved).
  final DateTime? resolvedAt;

  /// When the request expires (auto-cancel if no helper accepts).
  final DateTime expiresAt;

  /// Whether the helper has marked "on the way".
  final bool helperOnTheWay;

  /// Last updated timestamp.
  final DateTime updatedAt;

  const HelpRequest({
    required this.id,
    required this.seekerUserId,
    required this.seekerName,
    this.seekerPhotoUrl,
    this.helperUserId,
    this.helperName,
    this.helperPhotoUrl,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.topic,
    required this.status,
    required this.createdAt,
    this.assignedAt,
    this.resolvedAt,
    required this.expiresAt,
    this.helperOnTheWay = false,
    required this.updatedAt,
  });

  /// Check if the request is still active (can be helped).
  bool get isActive =>
      status == HelpRequestStatus.open || status == HelpRequestStatus.inProgress;

  /// Check if the request is open for new helpers.
  bool get isOpen => status == HelpRequestStatus.open;

  /// Check if the request has been assigned to a helper.
  bool get hasHelper => helperUserId != null;

  /// Check if the request has expired.
  bool get isExpired =>
      status == HelpRequestStatus.expired ||
      (status == HelpRequestStatus.open && DateTime.now().isAfter(expiresAt));

  /// Creates a copy with updated fields.
  HelpRequest copyWith({
    String? id,
    String? seekerUserId,
    String? seekerName,
    String? seekerPhotoUrl,
    String? helperUserId,
    String? helperName,
    String? helperPhotoUrl,
    double? latitude,
    double? longitude,
    HelpRadius? radius,
    String? topic,
    HelpRequestStatus? status,
    DateTime? createdAt,
    DateTime? assignedAt,
    DateTime? resolvedAt,
    DateTime? expiresAt,
    bool? helperOnTheWay,
    DateTime? updatedAt,
  }) {
    return HelpRequest(
      id: id ?? this.id,
      seekerUserId: seekerUserId ?? this.seekerUserId,
      seekerName: seekerName ?? this.seekerName,
      seekerPhotoUrl: seekerPhotoUrl ?? this.seekerPhotoUrl,
      helperUserId: helperUserId ?? this.helperUserId,
      helperName: helperName ?? this.helperName,
      helperPhotoUrl: helperPhotoUrl ?? this.helperPhotoUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      topic: topic ?? this.topic,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      assignedAt: assignedAt ?? this.assignedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      helperOnTheWay: helperOnTheWay ?? this.helperOnTheWay,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        seekerUserId,
        seekerName,
        seekerPhotoUrl,
        helperUserId,
        helperName,
        helperPhotoUrl,
        latitude,
        longitude,
        radius,
        topic,
        status,
        createdAt,
        assignedAt,
        resolvedAt,
        expiresAt,
        helperOnTheWay,
        updatedAt,
      ];
}
