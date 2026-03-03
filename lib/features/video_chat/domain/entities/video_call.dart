import 'package:equatable/equatable.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'call_status.dart';

/// Represents a single video call session between two users.
///
/// Stored in Firestore under `video_calls/{callId}`.
/// Contains SDP offer/answer for WebRTC signaling and status tracking.
class VideoCall extends Equatable {
  /// Unique call identifier.
  final String id;

  /// UID of the user who initiated the call.
  final String callerId;

  /// Anonymous display name of the caller.
  final String callerName;

  /// Optional photo URL of the caller.
  final String? callerPhotoUrl;

  /// UID of the user being called.
  final String receiverId;

  /// Anonymous display name of the receiver.
  final String receiverName;

  /// Optional photo URL of the receiver.
  final String? receiverPhotoUrl;

  /// Current status of the call.
  final CallStatus status;

  /// SDP offer from the caller.
  final Map<String, dynamic>? offer;

  /// SDP answer from the receiver.
  final Map<String, dynamic>? answer;

  /// When the call was initiated.
  final DateTime createdAt;

  /// When the call was answered (null if not yet answered).
  final DateTime? answeredAt;

  /// When the call ended (null if still in progress).
  final DateTime? endedAt;

  const VideoCall({
    required this.id,
    required this.callerId,
    required this.callerName,
    this.callerPhotoUrl,
    required this.receiverId,
    required this.receiverName,
    this.receiverPhotoUrl,
    required this.status,
    this.offer,
    this.answer,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
  });

  VideoCall copyWith({
    String? id,
    String? callerId,
    String? callerName,
    String? callerPhotoUrl,
    String? receiverId,
    String? receiverName,
    String? receiverPhotoUrl,
    CallStatus? status,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? answer,
    DateTime? createdAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    bool clearAnswer = false,
    bool clearAnsweredAt = false,
    bool clearEndedAt = false,
  }) {
    return VideoCall(
      id: id ?? this.id,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerPhotoUrl: callerPhotoUrl ?? this.callerPhotoUrl,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverPhotoUrl: receiverPhotoUrl ?? this.receiverPhotoUrl,
      status: status ?? this.status,
      offer: offer ?? this.offer,
      answer: clearAnswer ? null : (answer ?? this.answer),
      createdAt: createdAt ?? this.createdAt,
      answeredAt: clearAnsweredAt ? null : (answeredAt ?? this.answeredAt),
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerPhotoUrl': callerPhotoUrl,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverPhotoUrl': receiverPhotoUrl,
      'status': status.toFirestore(),
      'offer': offer,
      'answer': answer,
      'createdAt': createdAt.toIso8601String(),
      'answeredAt': answeredAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
    };
  }

  factory VideoCall.fromJson(String id, Map<String, dynamic> json) {
    return VideoCall(
      id: id,
      callerId: json['callerId'] as String? ?? '',
      callerName: json['callerName'] as String? ?? 'Anonymous',
      callerPhotoUrl: json['callerPhotoUrl'] as String?,
      receiverId: json['receiverId'] as String? ?? '',
      receiverName: json['receiverName'] as String? ?? 'Anonymous',
      receiverPhotoUrl: json['receiverPhotoUrl'] as String?,
      status: CallStatusX.fromFirestore(json['status'] as String? ?? 'ended'),
      offer: json['offer'] as Map<String, dynamic>?,
      answer: json['answer'] as Map<String, dynamic>?,
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      answeredAt: _parseDateTime(json['answeredAt']),
      endedAt: _parseDateTime(json['endedAt']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        callerId,
        callerName,
        callerPhotoUrl,
        receiverId,
        receiverName,
        receiverPhotoUrl,
        status,
        offer,
        answer,
        createdAt,
        answeredAt,
        endedAt,
      ];
}
