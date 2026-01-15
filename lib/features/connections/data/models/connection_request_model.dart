import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/connection_request.dart';

/// Firestore model for ConnectionRequest entity.
/// 
/// Firestore Schema:
/// ```
/// connection_requests/{requestId}
///   - senderId: string
///   - receiverId: string
///   - status: string ('pending', 'accepted', 'rejected', 'cancelled', 'expired')
///   - sentAt: timestamp
///   - respondedAt: timestamp?
///   - expiresAt: timestamp
///   - message: string?
///   - source: string?
///   - senderDisplayName: string?
///   - senderPhotoUrl: string?
///   - receiverDisplayName: string?
///   - receiverPhotoUrl: string?
/// 
/// Indexes needed:
///   - receiverId + status + sentAt (for inbox queries)
///   - senderId + status + sentAt (for sent requests)
///   - senderId + receiverId (for duplicate checks)
///   - expiresAt (for cleanup)
/// ```
class ConnectionRequestModel extends ConnectionRequest {
  const ConnectionRequestModel({
    required super.id,
    required super.senderId,
    required super.receiverId,
    required super.status,
    required super.sentAt,
    super.respondedAt,
    required super.expiresAt,
    super.message,
    super.source,
    super.senderDisplayName,
    super.senderPhotoUrl,
    super.receiverDisplayName,
    super.receiverPhotoUrl,
  });

  /// Creates model from Firestore document.
  factory ConnectionRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return ConnectionRequestModel(
      id: doc.id,
      senderId: data['senderId'] as String,
      receiverId: data['receiverId'] as String,
      status: _parseStatus(data['status'] as String),
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      respondedAt: data['respondedAt'] != null
          ? (data['respondedAt'] as Timestamp).toDate()
          : null,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      message: data['message'] as String?,
      source: data['source'] as String?,
      senderDisplayName: data['senderDisplayName'] as String?,
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      receiverDisplayName: data['receiverDisplayName'] as String?,
      receiverPhotoUrl: data['receiverPhotoUrl'] as String?,
    );
  }

  /// Creates model from ConnectionRequest entity.
  factory ConnectionRequestModel.fromEntity(ConnectionRequest request) {
    return ConnectionRequestModel(
      id: request.id,
      senderId: request.senderId,
      receiverId: request.receiverId,
      status: request.status,
      sentAt: request.sentAt,
      respondedAt: request.respondedAt,
      expiresAt: request.expiresAt,
      message: request.message,
      source: request.source,
      senderDisplayName: request.senderDisplayName,
      senderPhotoUrl: request.senderPhotoUrl,
      receiverDisplayName: request.receiverDisplayName,
      receiverPhotoUrl: request.receiverPhotoUrl,
    );
  }

  /// Converts to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'status': status.name,
      'sentAt': Timestamp.fromDate(sentAt),
      'respondedAt':
          respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'message': message,
      'source': source,
      'senderDisplayName': senderDisplayName,
      'senderPhotoUrl': senderPhotoUrl,
      'receiverDisplayName': receiverDisplayName,
      'receiverPhotoUrl': receiverPhotoUrl,
    };
  }

  /// Converts to ConnectionRequest entity.
  ConnectionRequest toEntity() {
    return ConnectionRequest(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      status: status,
      sentAt: sentAt,
      respondedAt: respondedAt,
      expiresAt: expiresAt,
      message: message,
      source: source,
      senderDisplayName: senderDisplayName,
      senderPhotoUrl: senderPhotoUrl,
      receiverDisplayName: receiverDisplayName,
      receiverPhotoUrl: receiverPhotoUrl,
    );
  }

  static ConnectionRequestStatus _parseStatus(String status) {
    return ConnectionRequestStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => ConnectionRequestStatus.expired,
    );
  }
}

/// Model for tracking user's request rate limits.
/// 
/// Firestore Schema:
/// ```
/// users/{userId}/rate_limits/connection_requests
///   - hourlyCount: number
///   - hourlyResetAt: timestamp
///   - dailyCount: number
///   - dailyResetAt: timestamp
///   - lastRequestAt: timestamp
/// ```
class RequestRateLimitModel {
  final int hourlyCount;
  final DateTime hourlyResetAt;
  final int dailyCount;
  final DateTime dailyResetAt;
  final DateTime lastRequestAt;

  const RequestRateLimitModel({
    required this.hourlyCount,
    required this.hourlyResetAt,
    required this.dailyCount,
    required this.dailyResetAt,
    required this.lastRequestAt,
  });

  factory RequestRateLimitModel.initial() {
    final now = DateTime.now();
    return RequestRateLimitModel(
      hourlyCount: 0,
      hourlyResetAt: now.add(const Duration(hours: 1)),
      dailyCount: 0,
      dailyResetAt: DateTime(now.year, now.month, now.day + 1),
      lastRequestAt: now,
    );
  }

  factory RequestRateLimitModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return RequestRateLimitModel.initial();

    return RequestRateLimitModel(
      hourlyCount: data['hourlyCount'] as int? ?? 0,
      hourlyResetAt: data['hourlyResetAt'] != null
          ? (data['hourlyResetAt'] as Timestamp).toDate()
          : DateTime.now().add(const Duration(hours: 1)),
      dailyCount: data['dailyCount'] as int? ?? 0,
      dailyResetAt: data['dailyResetAt'] != null
          ? (data['dailyResetAt'] as Timestamp).toDate()
          : DateTime(DateTime.now().year, DateTime.now().month,
              DateTime.now().day + 1),
      lastRequestAt: data['lastRequestAt'] != null
          ? (data['lastRequestAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'hourlyCount': hourlyCount,
      'hourlyResetAt': Timestamp.fromDate(hourlyResetAt),
      'dailyCount': dailyCount,
      'dailyResetAt': Timestamp.fromDate(dailyResetAt),
      'lastRequestAt': Timestamp.fromDate(lastRequestAt),
    };
  }

  /// Checks if rate limits have been exceeded.
  bool get isHourlyLimitExceeded =>
      DateTime.now().isBefore(hourlyResetAt) &&
      hourlyCount >= ConnectionRateLimits.maxRequestsPerHour;

  bool get isDailyLimitExceeded =>
      DateTime.now().isBefore(dailyResetAt) &&
      dailyCount >= ConnectionRateLimits.maxRequestsPerDay;

  bool get canSendRequest => !isHourlyLimitExceeded && !isDailyLimitExceeded;

  /// Creates updated model after sending a request.
  RequestRateLimitModel increment() {
    final now = DateTime.now();

    // Reset hourly if expired
    int newHourlyCount = hourlyCount;
    DateTime newHourlyReset = hourlyResetAt;
    if (now.isAfter(hourlyResetAt)) {
      newHourlyCount = 0;
      newHourlyReset = now.add(const Duration(hours: 1));
    }

    // Reset daily if expired
    int newDailyCount = dailyCount;
    DateTime newDailyReset = dailyResetAt;
    if (now.isAfter(dailyResetAt)) {
      newDailyCount = 0;
      newDailyReset = DateTime(now.year, now.month, now.day + 1);
    }

    return RequestRateLimitModel(
      hourlyCount: newHourlyCount + 1,
      hourlyResetAt: newHourlyReset,
      dailyCount: newDailyCount + 1,
      dailyResetAt: newDailyReset,
      lastRequestAt: now,
    );
  }
}
