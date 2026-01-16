import 'package:equatable/equatable.dart';

/// Status of a connection request.
enum ConnectionRequestStatus {
  /// Request is pending response.
  pending,

  /// Request was accepted (connection created).
  accepted,

  /// Request was rejected by recipient.
  rejected,

  /// Request was cancelled by sender.
  cancelled,

  /// Request expired (no response within time limit).
  expired,
}

/// Entity representing a connection request from one user to another.
///
/// Requests require mutual consent - the recipient must accept for a
/// connection to be established.
class ConnectionRequest extends Equatable {
  /// Unique request ID.
  final String id;

  /// User ID who sent the request.
  final String senderId;

  /// User ID who received the request.
  final String receiverId;

  /// Current status of the request.
  final ConnectionRequestStatus status;

  /// When the request was sent.
  final DateTime sentAt;

  /// When the request was responded to (accepted/rejected).
  final DateTime? respondedAt;

  /// When the request expires (for auto-cleanup).
  final DateTime expiresAt;

  /// Optional message from sender.
  final String? message;

  /// Context: where the request originated (e.g., 'nearby', 'search', 'profile').
  final String? source;

  /// Sender's display name (denormalized for notifications).
  final String? senderDisplayName;

  /// Sender's photo URL (denormalized for UI).
  final String? senderPhotoUrl;

  /// Receiver's display name (denormalized for sender's UI).
  final String? receiverDisplayName;

  /// Receiver's photo URL (denormalized for sender's UI).
  final String? receiverPhotoUrl;

  const ConnectionRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.sentAt,
    this.respondedAt,
    required this.expiresAt,
    this.message,
    this.source,
    this.senderDisplayName,
    this.senderPhotoUrl,
    this.receiverDisplayName,
    this.receiverPhotoUrl,
  });

  /// Whether this request can still be responded to.
  bool get isActionable =>
      status == ConnectionRequestStatus.pending &&
      DateTime.now().isBefore(expiresAt);

  /// Whether this request has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Duration until expiration.
  Duration get timeUntilExpiration => expiresAt.difference(DateTime.now());

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  ConnectionRequest copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    ConnectionRequestStatus? status,
    DateTime? sentAt,
    Object? respondedAt = _sentinel,
    DateTime? expiresAt,
    Object? message = _sentinel,
    Object? source = _sentinel,
    Object? senderDisplayName = _sentinel,
    Object? senderPhotoUrl = _sentinel,
    Object? receiverDisplayName = _sentinel,
    Object? receiverPhotoUrl = _sentinel,
  }) {
    return ConnectionRequest(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      status: status ?? this.status,
      sentAt: sentAt ?? this.sentAt,
      respondedAt: respondedAt == _sentinel
          ? this.respondedAt
          : respondedAt as DateTime?,
      expiresAt: expiresAt ?? this.expiresAt,
      message: message == _sentinel ? this.message : message as String?,
      source: source == _sentinel ? this.source : source as String?,
      senderDisplayName: senderDisplayName == _sentinel
          ? this.senderDisplayName
          : senderDisplayName as String?,
      senderPhotoUrl: senderPhotoUrl == _sentinel
          ? this.senderPhotoUrl
          : senderPhotoUrl as String?,
      receiverDisplayName: receiverDisplayName == _sentinel
          ? this.receiverDisplayName
          : receiverDisplayName as String?,
      receiverPhotoUrl: receiverPhotoUrl == _sentinel
          ? this.receiverPhotoUrl
          : receiverPhotoUrl as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        senderId,
        receiverId,
        status,
        sentAt,
        respondedAt,
        expiresAt,
        message,
        source,
        senderDisplayName,
        senderPhotoUrl,
        receiverDisplayName,
        receiverPhotoUrl,
      ];
}

/// Rate limit configuration for connection requests.
class ConnectionRateLimits {
  /// Maximum requests a user can send per hour.
  static const int maxRequestsPerHour = 10;

  /// Maximum requests a user can send per day.
  static const int maxRequestsPerDay = 30;

  /// Cooldown period after being rejected (hours).
  static const int rejectionCooldownHours = 24;

  /// Request expiration time (days).
  static const int requestExpirationDays = 7;

  /// Minimum time between requests to same user (hours).
  static const int sameUserCooldownHours = 24;
}
