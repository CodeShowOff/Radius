import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/connections/domain/entities/connection.dart';

void main() {
  group('Connection Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid Connection instance', () {
      final connection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      expect(connection.id, 'user-123_user-456');
      expect(connection.userId1, 'user-123');
      expect(connection.userId2, 'user-456');
      expect(connection.status, ConnectionStatus.connected);
      expect(connection.initiatedBy, 'user-123');
    });

    test('should support value equality', () {
      final connection1 = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      final connection2 = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      expect(connection1, equals(connection2));
    });

    test('should handle different connection statuses', () {
      final connectedConnection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      final blockedConnection = Connection(
        id: 'user-123_user-789',
        userId1: 'user-123',
        userId2: 'user-789',
        status: ConnectionStatus.blocked,
        blockedBy: 'user-123',
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      final disconnectedConnection = Connection(
        id: 'user-123_user-999',
        userId1: 'user-123',
        userId2: 'user-999',
        status: ConnectionStatus.disconnected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-999',
      );

      expect(connectedConnection.status, ConnectionStatus.connected);
      expect(blockedConnection.status, ConnectionStatus.blocked);
      expect(blockedConnection.blockedBy, 'user-123');
      expect(disconnectedConnection.status, ConnectionStatus.disconnected);
    });

    test('getOtherUserId should return correct user ID', () {
      final connection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      expect(connection.getOtherUserId('user-123'), 'user-456');
      expect(connection.getOtherUserId('user-456'), 'user-123');
    });

    test('createConnectionId should create canonical ID', () {
      final id1 = Connection.createConnectionId('user-123', 'user-456');
      final id2 = Connection.createConnectionId('user-456', 'user-123');

      expect(id1, 'user-123_user-456');
      expect(id2, 'user-123_user-456'); // same regardless of order
    });

    test('hasUser should check if user is part of connection', () {
      final connection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      expect(connection.hasUser('user-123'), true);
      expect(connection.hasUser('user-456'), true);
      expect(connection.hasUser('user-789'), false);
    });

    test('should handle messaging permission', () {
      final canMessageConnection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        canMessage: true,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      final noMessageConnection = Connection(
        id: 'user-123_user-789',
        userId1: 'user-123',
        userId2: 'user-789',
        status: ConnectionStatus.connected,
        canMessage: false,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      expect(canMessageConnection.canMessage, true);
      expect(noMessageConnection.canMessage, false);
    });

    test('should handle location sharing permission', () {
      final shareLocationConnection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        shareLocation: true,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      final noShareConnection = Connection(
        id: 'user-123_user-789',
        userId1: 'user-123',
        userId2: 'user-789',
        status: ConnectionStatus.connected,
        shareLocation: false,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      expect(shareLocationConnection.shareLocation, true);
      expect(noShareConnection.shareLocation, false);
    });

    test('copyWith should create updated instance', () {
      final connection = Connection(
        id: 'user-123_user-456',
        userId1: 'user-123',
        userId2: 'user-456',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-123',
      );

      final updatedConnection = connection.copyWith(
        status: ConnectionStatus.blocked,
        blockedBy: 'user-456',
      );

      expect(updatedConnection.status, ConnectionStatus.blocked);
      expect(updatedConnection.blockedBy, 'user-456');
      expect(updatedConnection.id, connection.id); // unchanged
    });

    test('should distinguish between different connections', () {
      final connection1 = Connection(
        id: 'user-1_user-2',
        userId1: 'user-1',
        userId2: 'user-2',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-1',
      );

      final connection2 = Connection(
        id: 'user-3_user-4',
        userId1: 'user-3',
        userId2: 'user-4',
        status: ConnectionStatus.connected,
        connectedAt: testDate,
        updatedAt: testDate,
        initiatedBy: 'user-3',
      );

      expect(connection1, isNot(equals(connection2)));
    });
  });
}
