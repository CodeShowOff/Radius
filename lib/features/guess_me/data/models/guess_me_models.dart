import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/guess_me_session.dart';

/// Firestore model for GuessMe sessions.
class GuessmeSessionModel {
  final String id;
  final List<String> players;
  final String player1Id;
  final String player2Id;
  final String player1Name;
  final String player2Name;
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final DateTime? endedAt;
  final bool player1Guessed;
  final bool player2Guessed;
  final bool guessCheckPending;
  final String? guessCheckInitiator;
  final bool awaitingConnectionConfirmations;
  final String? connectionRequestId;
  final bool? player1WantsToConnect;
  final bool? player2WantsToConnect;
  final bool? mutualConnectionSuccess;

  const GuessmeSessionModel({
    required this.id,
    required this.players,
    required this.player1Id,
    required this.player2Id,
    required this.player1Name,
    required this.player2Name,
    required this.status,
    this.createdAt,
    this.expiresAt,
    this.endedAt,
    this.player1Guessed = false,
    this.player2Guessed = false,
    this.guessCheckPending = false,
    this.guessCheckInitiator,
    this.awaitingConnectionConfirmations = false,
    this.connectionRequestId,
    this.player1WantsToConnect,
    this.player2WantsToConnect,
    this.mutualConnectionSuccess,
  });

  factory GuessmeSessionModel.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>? ?? {};

    DateTime? safeDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return GuessmeSessionModel(
      id: data['id'] as String? ?? snap.id,
      players: List<String>.from(data['players'] ?? <String>[]),
      player1Id: data['player1Id'] as String? ?? '',
      player2Id: data['player2Id'] as String? ?? '',
      player1Name: data['player1Name'] as String? ?? 'Mystery User A',
      player2Name: data['player2Name'] as String? ?? 'Mystery User B',
      status: data['status'] as String? ?? 'active',
      createdAt: safeDate(data['createdAt']),
      expiresAt: safeDate(data['expiresAt']),
      endedAt: safeDate(data['endedAt']),
      player1Guessed: data['player1Guessed'] as bool? ?? false,
      player2Guessed: data['player2Guessed'] as bool? ?? false,
      guessCheckPending: data['guessCheckPending'] as bool? ?? false,
      guessCheckInitiator: data['guessCheckInitiator'] as String?,
      awaitingConnectionConfirmations: data['awaitingConnectionConfirmations'] as bool? ?? false,
      connectionRequestId: data['connectionRequestId'] as String?,
      player1WantsToConnect: data['player1WantsToConnect'] as bool?,
      player2WantsToConnect: data['player2WantsToConnect'] as bool?,
      mutualConnectionSuccess: data['mutualConnectionSuccess'] as bool?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'players': players,
      'player1Id': player1Id,
      'player2Id': player2Id,
      'player1Name': player1Name,
      'player2Name': player2Name,
      'status': status,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'player1Guessed': player1Guessed,
      'player2Guessed': player2Guessed,
      'guessCheckPending': guessCheckPending,
      'guessCheckInitiator': guessCheckInitiator,
      'awaitingConnectionConfirmations': awaitingConnectionConfirmations,
      'connectionRequestId': connectionRequestId,
      'player1WantsToConnect': player1WantsToConnect,
      'player2WantsToConnect': player2WantsToConnect,
      'mutualConnectionSuccess': mutualConnectionSuccess,
    };
  }

  GuessmeSession toEntity() {
    GuessmeSessionStatus sessionStatus;
    switch (status) {
      case 'active':
        sessionStatus = GuessmeSessionStatus.active;
        break;
      case 'completed':
        sessionStatus = GuessmeSessionStatus.completed;
        break;
      case 'cancelled':
        sessionStatus = GuessmeSessionStatus.cancelled;
        break;
      case 'expired':
        sessionStatus = GuessmeSessionStatus.expired;
        break;
      case 'waiting':
        sessionStatus = GuessmeSessionStatus.waiting;
        break;
      default:
        sessionStatus = GuessmeSessionStatus.active;
    }

    return GuessmeSession(
      id: id,
      player1Id: player1Id,
      player1Name: player1Name,
      player2Id: player2Id,
      player2Name: player2Name,
      status: sessionStatus,
      createdAt: createdAt ?? DateTime.now(),
      startedAt: createdAt,
      expiresAt: expiresAt,
      endedAt: endedAt,
      player1Guessed: player1Guessed,
      player2Guessed: player2Guessed,
      guessCheckInitiator: guessCheckInitiator,
      guessCheckPending: guessCheckPending,
      awaitingConnectionConfirmations: awaitingConnectionConfirmations,
      player1WantsToConnect: player1WantsToConnect,
      player2WantsToConnect: player2WantsToConnect,
      mutualConnectionSuccess: mutualConnectionSuccess,
    );
  }
}

/// Firestore model for GuessMe messages.
class GuessmeMessageModel {
  final String id;
  final String sessionId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final GuessmeMessageType type;

  const GuessmeMessageModel({
    required this.id,
    required this.sessionId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.type = GuessmeMessageType.chat,
  });

  factory GuessmeMessageModel.fromFirestore(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>? ?? {};

    DateTime? safeDate(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    GuessmeMessageType type = GuessmeMessageType.chat;
    final typeStr = data['type'] as String?;
    if (typeStr == 'system') {
      type = GuessmeMessageType.system;
    } else if (typeStr == 'guessCheck') {
      type = GuessmeMessageType.guessCheck;
    }

    return GuessmeMessageModel(
      id: data['id'] as String? ?? snap.id,
      sessionId: data['sessionId'] as String? ?? '',
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: safeDate(data['sentAt']) ?? DateTime.now(),
      type: type,
    );
  }

  Map<String, dynamic> toFirestore({bool useServerTimestamp = false}) {
    return {
      'id': id,
      'sessionId': sessionId,
      'senderId': senderId,
      'text': text,
      'sentAt': useServerTimestamp ? FieldValue.serverTimestamp() : Timestamp.fromDate(sentAt),
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
}
