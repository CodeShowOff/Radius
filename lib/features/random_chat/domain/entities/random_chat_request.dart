import 'package:equatable/equatable.dart';

/// Status of a random chat request.
enum RandomChatRequestStatus {
  pending,
  accepted,
  rejected,
  expired,
}

/// A chat request sent from one user to another within the daily random chat cycle.
class RandomChatRequest extends Equatable {
  final String id;
  final String senderId;
  final String receiverId;
  final String senderDisplayName;
  final String? senderPhotoUrl;
  final String receiverDisplayName;
  final String? receiverPhotoUrl;
  final RandomChatRequestStatus status;
  final String dateKey; // e.g. '2026-02-09'
  final DateTime createdAt;
  final DateTime? respondedAt;

  const RandomChatRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.senderDisplayName,
    this.senderPhotoUrl,
    required this.receiverDisplayName,
    this.receiverPhotoUrl,
    required this.status,
    required this.dateKey,
    required this.createdAt,
    this.respondedAt,
  });

  RandomChatRequest copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? senderDisplayName,
    String? senderPhotoUrl,
    String? receiverDisplayName,
    String? receiverPhotoUrl,
    RandomChatRequestStatus? status,
    String? dateKey,
    DateTime? createdAt,
    DateTime? respondedAt,
  }) {
    return RandomChatRequest(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
      senderPhotoUrl: senderPhotoUrl ?? this.senderPhotoUrl,
      receiverDisplayName: receiverDisplayName ?? this.receiverDisplayName,
      receiverPhotoUrl: receiverPhotoUrl ?? this.receiverPhotoUrl,
      status: status ?? this.status,
      dateKey: dateKey ?? this.dateKey,
      createdAt: createdAt ?? this.createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  /// Convert to JSON for caching.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'senderDisplayName': senderDisplayName,
      'senderPhotoUrl': senderPhotoUrl,
      'receiverDisplayName': receiverDisplayName,
      'receiverPhotoUrl': receiverPhotoUrl,
      'status': status.name,
      'dateKey': dateKey,
      'createdAt': createdAt.toIso8601String(),
      'respondedAt': respondedAt?.toIso8601String(),
    };
  }

  /// Create from JSON.
  factory RandomChatRequest.fromJson(Map<String, dynamic> json) {
    return RandomChatRequest(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      senderDisplayName: json['senderDisplayName'] as String,
      senderPhotoUrl: json['senderPhotoUrl'] as String?,
      receiverDisplayName: json['receiverDisplayName'] as String,
      receiverPhotoUrl: json['receiverPhotoUrl'] as String?,
      status: RandomChatRequestStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RandomChatRequestStatus.pending,
      ),
      dateKey: json['dateKey'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      respondedAt: json['respondedAt'] != null
          ? DateTime.parse(json['respondedAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        senderId,
        receiverId,
        senderDisplayName,
        senderPhotoUrl,
        receiverDisplayName,
        receiverPhotoUrl,
        status,
        dateKey,
        createdAt,
        respondedAt,
      ];
}
