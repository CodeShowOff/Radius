import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/guess_me/domain/entities/guess_me_session.dart';

void main() {
  group('GuessmeSession Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid GuessmeSession instance', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
      );

      expect(session.id, 'session-123');
      expect(session.player1Id, 'user-123');
      expect(session.status, GuessmeSessionStatus.active);
      expect(session.createdAt, testDate);
    });

    test('should support value equality', () {
      final session1 = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
      );

      final session2 = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
      );

      expect(session1, equals(session2));
    });

    test('should handle different session statuses', () {
      final waitingSession = GuessmeSession(
        id: 'session-1',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.waiting,
        createdAt: testDate,
      );

      final activeSession = GuessmeSession(
        id: 'session-2',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
        startedAt: testDate,
      );

      final completedSession = GuessmeSession(
        id: 'session-3',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.completed,
        createdAt: testDate,
        startedAt: testDate,
        endedAt: testDate.add(const Duration(minutes: 30)),
      );

      final cancelledSession = GuessmeSession(
        id: 'session-4',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.cancelled,
        createdAt: testDate,
        endedAt: testDate.add(const Duration(minutes: 1)),
      );

      expect(waitingSession.status, GuessmeSessionStatus.waiting);
      expect(activeSession.status, GuessmeSessionStatus.active);
      expect(completedSession.status, GuessmeSessionStatus.completed);
      expect(cancelledSession.status, GuessmeSessionStatus.cancelled);
    });

    test('should handle two players', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player1Name: 'Player One',
        player2Id: 'user-456',
        player2Name: 'Player Two',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
      );

      expect(session.player1Id, 'user-123');
      expect(session.player1Name, 'Player One');
      expect(session.player2Id, 'user-456');
      expect(session.player2Name, 'Player Two');
    });

    test('should track guess status for both players', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.active,
        player1Guessed: true,
        player2Guessed: false,
        createdAt: testDate,
      );

      expect(session.player1Guessed, true);
      expect(session.player2Guessed, false);
    });

    test('should handle guess check flow', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.active,
        guessCheckPending: true,
        guessCheckInitiator: 'user-123',
        createdAt: testDate,
      );

      expect(session.guessCheckPending, true);
      expect(session.guessCheckInitiator, 'user-123');
    });

    test('should handle connection confirmation flow', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.active,
        awaitingConnectionConfirmations: true,
        player1WantsToConnect: true,
        player2WantsToConnect: false,
        createdAt: testDate,
      );

      expect(session.awaitingConnectionConfirmations, true);
      expect(session.player1WantsToConnect, true);
      expect(session.player2WantsToConnect, false);
    });

    test('should track mutual connection success', () {
      final successSession = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.completed,
        player1WantsToConnect: true,
        player2WantsToConnect: true,
        mutualConnectionSuccess: true,
        createdAt: testDate,
      );

      final failedSession = GuessmeSession(
        id: 'session-456',
        player1Id: 'user-789',
        player2Id: 'user-101',
        status: GuessmeSessionStatus.completed,
        player1WantsToConnect: true,
        player2WantsToConnect: false,
        mutualConnectionSuccess: false,
        createdAt: testDate,
      );

      expect(successSession.mutualConnectionSuccess, true);
      expect(failedSession.mutualConnectionSuccess, false);
    });

    test('should track session timeline', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.completed,
        createdAt: testDate,
        startedAt: testDate.add(const Duration(minutes: 1)),
        expiresAt: testDate.add(const Duration(hours: 1)),
        endedAt: testDate.add(const Duration(minutes: 30)),
      );

      expect(session.createdAt, testDate);
      expect(session.startedAt, testDate.add(const Duration(minutes: 1)));
      expect(session.expiresAt, testDate.add(const Duration(hours: 1)));
      expect(session.endedAt, testDate.add(const Duration(minutes: 30)));
    });

    test('isActive should return correct value', () {
      final activeSession = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
        startedAt: testDate,
        expiresAt: DateTime.now().add(const Duration(hours: 1)), // Future expiry
      );

      final completedSession = GuessmeSession(
        id: 'session-456',
        player1Id: 'user-789',
        status: GuessmeSessionStatus.completed,
        createdAt: testDate,
      );

      expect(activeSession.isActive, true);
      expect(completedSession.isActive, false);
    });

    test('should handle session expiry', () {
      final expiredSession = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        player2Id: 'user-456',
        status: GuessmeSessionStatus.expired,
        createdAt: testDate,
        startedAt: testDate,
        expiresAt: testDate.add(const Duration(hours: 1)),
        endedAt: testDate.add(const Duration(hours: 1)),
      );

      expect(expiredSession.status, GuessmeSessionStatus.expired);
      expect(expiredSession.endedAt, expiredSession.expiresAt);
    });

    test('copyWith should create updated instance', () {
      final session = GuessmeSession(
        id: 'session-123',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.waiting,
        createdAt: testDate,
      );

      final updatedSession = session.copyWith(
        player2Id: 'user-456',
        status: GuessmeSessionStatus.active,
        startedAt: testDate.add(const Duration(seconds: 30)),
      );

      expect(updatedSession.player2Id, 'user-456');
      expect(updatedSession.status, GuessmeSessionStatus.active);
      expect(updatedSession.startedAt, testDate.add(const Duration(seconds: 30)));
      expect(updatedSession.id, session.id); // unchanged
    });

    test('should distinguish between different sessions', () {
      final session1 = GuessmeSession(
        id: 'session-1',
        player1Id: 'user-123',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
      );

      final session2 = GuessmeSession(
        id: 'session-2',
        player1Id: 'user-456',
        status: GuessmeSessionStatus.active,
        createdAt: testDate,
      );

      expect(session1, isNot(equals(session2)));
    });
  });
}
