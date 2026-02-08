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
