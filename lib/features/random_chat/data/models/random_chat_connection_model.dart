import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/random_chat_connection.dart';

/// Firestore model for [RandomChatConnection].
class RandomChatConnectionModel extends RandomChatConnection {
  const RandomChatConnectionModel({
    required super.id,
    required super.user1Id,
    required super.user2Id,
    required super.user1DisplayName,
    super.user1PhotoUrl,
    required super.user2DisplayName,
    super.user2PhotoUrl,
    required super.dateKey,
    required super.createdAt,
  });

  /// Creates model from Firestore document.
  factory RandomChatConnectionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RandomChatConnectionModel(
      id: doc.id,
      user1Id: data['user1Id'] as String? ?? '',
      user2Id: data['user2Id'] as String? ?? '',
      user1DisplayName: data['user1DisplayName'] as String? ?? 'Unknown',
      user1PhotoUrl: data['user1PhotoUrl'] as String?,
      user2DisplayName: data['user2DisplayName'] as String? ?? 'Unknown',
      user2PhotoUrl: data['user2PhotoUrl'] as String?,
      dateKey: data['dateKey'] as String? ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Converts to Firestore document map.
  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'user1Id': user1Id,
      'user2Id': user2Id,
      'user1DisplayName': user1DisplayName,
      'user1PhotoUrl': user1PhotoUrl,
      'user2DisplayName': user2DisplayName,
      'user2PhotoUrl': user2PhotoUrl,
      'dateKey': dateKey,
      'participantIds': [user1Id, user2Id],
      'createdAt':
          useServerTimestamp ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt),
    };
  }

  /// Converts to domain entity.
  RandomChatConnection toEntity() {
    return RandomChatConnection(
      id: id,
      user1Id: user1Id,
      user2Id: user2Id,
      user1DisplayName: user1DisplayName,
      user1PhotoUrl: user1PhotoUrl,
      user2DisplayName: user2DisplayName,
      user2PhotoUrl: user2PhotoUrl,
      dateKey: dateKey,
      createdAt: createdAt,
    );
  }
}
