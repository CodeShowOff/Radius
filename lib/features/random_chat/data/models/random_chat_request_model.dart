import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/random_chat_request.dart';

/// Firestore model for [RandomChatRequest].
class RandomChatRequestModel extends RandomChatRequest {
  const RandomChatRequestModel({
    required super.id,
    required super.senderId,
    required super.receiverId,
    required super.senderDisplayName,
    super.senderPhotoUrl,
    required super.receiverDisplayName,
    super.receiverPhotoUrl,
    required super.status,
    required super.dateKey,
    required super.createdAt,
    super.respondedAt,
  });

  /// Creates model from Firestore document.
  factory RandomChatRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RandomChatRequestModel(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      senderDisplayName: data['senderDisplayName'] as String? ?? 'Unknown',
      senderPhotoUrl: data['senderPhotoUrl'] as String?,
      receiverDisplayName: data['receiverDisplayName'] as String? ?? 'Unknown',
      receiverPhotoUrl: data['receiverPhotoUrl'] as String?,
      status: _parseStatus(data['status'] as String?),
      dateKey: data['dateKey'] as String? ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Creates model from domain entity.
  factory RandomChatRequestModel.fromEntity(RandomChatRequest entity) {
    return RandomChatRequestModel(
      id: entity.id,
      senderId: entity.senderId,
      receiverId: entity.receiverId,
      senderDisplayName: entity.senderDisplayName,
      senderPhotoUrl: entity.senderPhotoUrl,
      receiverDisplayName: entity.receiverDisplayName,
      receiverPhotoUrl: entity.receiverPhotoUrl,
      status: entity.status,
      dateKey: entity.dateKey,
      createdAt: entity.createdAt,
      respondedAt: entity.respondedAt,
    );
  }

  /// Converts to Firestore document map.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'senderDisplayName': senderDisplayName,
      'senderPhotoUrl': senderPhotoUrl,
      'receiverDisplayName': receiverDisplayName,
      'receiverPhotoUrl': receiverPhotoUrl,
      'status': status.name,
      'dateKey': dateKey,
      'createdAt':
          useServerTimestamp ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt),
      if (respondedAt != null)
        'respondedAt': Timestamp.fromDate(respondedAt!),
    };
  }

  /// Converts to domain entity.
  RandomChatRequest toEntity() {
    return RandomChatRequest(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      senderDisplayName: senderDisplayName,
      senderPhotoUrl: senderPhotoUrl,
      receiverDisplayName: receiverDisplayName,
      receiverPhotoUrl: receiverPhotoUrl,
      status: status,
      dateKey: dateKey,
      createdAt: createdAt,
      respondedAt: respondedAt,
    );
  }

  static RandomChatRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return RandomChatRequestStatus.accepted;
      case 'rejected':
        return RandomChatRequestStatus.rejected;
      case 'expired':
        return RandomChatRequestStatus.expired;
      case 'pending':
      default:
        return RandomChatRequestStatus.pending;
    }
  }
}
