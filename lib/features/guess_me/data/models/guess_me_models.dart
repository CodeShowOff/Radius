import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/guess_me_session.dart';

/// Firestore model for GuessMe session.
class GuessmeSessionModel extends GuessmeSession {
  const GuessmeSessionModel({
    required super.id,
    required super.player1Id,
    super.player1Name,
    super.player2Id,
    super.player2Name,
    required super.status,
    required super.createdAt,
    super.startedAt,
    super.expiresAt,
    super.endedAt,
    super.player1Guessed,
    super.player2Guessed,
    super.guessCheckInitiator,
    super.guessCheckPending,
  });

  factory GuessmeSessionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return GuessmeSessionModel(
      id: doc.id,
      player1Id: data['player1Id'] as String,
      player1Name: data['player1Name'] as String?,
      player2Id: data['player2Id'] as String?,
      player2Name: data['player2Name'] as String?,
      status: _parseStatus(data['status'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      startedAt: data['startedAt'] != null
          ? (data['startedAt'] as Timestamp).toDate()
          : null,
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
      endedAt: data['endedAt'] != null
          ? (data['endedAt'] as Timestamp).toDate()
          : null,
      player1Guessed: data['player1Guessed'] as bool? ?? false,
      player2Guessed: data['player2Guessed'] as bool? ?? false,
      guessCheckInitiator: data['guessCheckInitiator'] as String?,
      guessCheckPending: data['guessCheckPending'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'player1Id': player1Id,
      'player1Name': player1Name,
      'player2Id': player2Id,
      'player2Name': player2Name,
      'status': status.name,
      'createdAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt),
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'player1Guessed': player1Guessed,
      'player2Guessed': player2Guessed,
      'guessCheckInitiator': guessCheckInitiator,
      'guessCheckPending': guessCheckPending,
      // Denormalized for queries
      'players': [player1Id, if (player2Id != null) player2Id],
    };
  }

  GuessmeSession toEntity() {
    return GuessmeSession(
      id: id,
      player1Id: player1Id,
      player1Name: player1Name,
      player2Id: player2Id,
      player2Name: player2Name,
      status: status,
      createdAt: createdAt,
      startedAt: startedAt,
      expiresAt: expiresAt,
      endedAt: endedAt,
      player1Guessed: player1Guessed,
      player2Guessed: player2Guessed,
      guessCheckInitiator: guessCheckInitiator,
      guessCheckPending: guessCheckPending,
    );
  }

  static GuessmeSessionStatus _parseStatus(String status) {
    return GuessmeSessionStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => GuessmeSessionStatus.expired,
    );
  }
}

/// Firestore model for GuessMe message.
class GuessmeMessageModel extends GuessmeMessage {
  const GuessmeMessageModel({
    required super.id,
    required super.sessionId,
    required super.senderId,
    required super.text,
    required super.sentAt,
    super.type,
  });

  factory GuessmeMessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return GuessmeMessageModel(
      id: doc.id,
      sessionId: data['sessionId'] as String,
      senderId: data['senderId'] as String,
      text: data['text'] as String,
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      type: _parseMessageType(data['type'] as String?),
    );
  }

  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'sessionId': sessionId,
      'senderId': senderId,
      'text': text,
      'sentAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(sentAt),
      'type': type.name,
    };
  }

  GuessmeMessage toEntity() {
    return GuessmeMessage(
      id: id,
      sessionId: sessionId,
      senderId: senderId,
      text: text,
      sentAt: sentAt,
      type: type,
    );
  }

  static GuessmeMessageType _parseMessageType(String? type) {
    if (type == null) return GuessmeMessageType.chat;
    return GuessmeMessageType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => GuessmeMessageType.chat,
    );
  }
}
