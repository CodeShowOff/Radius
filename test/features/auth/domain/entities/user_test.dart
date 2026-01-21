import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/auth/domain/entities/user.dart';

void main() {
  group('User Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid User instance', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        displayName: 'Test User',
        username: 'testuser',
        createdAt: testDate,
      );

      expect(user.id, 'user-123');
      expect(user.email, 'test@example.com');
      expect(user.displayName, 'Test User');
      expect(user.username, 'testuser');
      expect(user.createdAt, testDate);
    });

    test('should support value equality', () {
      final user1 = User(
        id: 'user-123',
        email: 'test@example.com',
        username: 'testuser',
        createdAt: testDate,
      );

      final user2 = User(
        id: 'user-123',
        email: 'test@example.com',
        username: 'testuser',
        createdAt: testDate,
      );

      expect(user1, equals(user2));
    });

    test('should have correct props for equality', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        displayName: 'Test User',
        username: 'testuser',
        createdAt: testDate,
      );

      expect(user.props, [
        'user-123',
        'test@example.com',
        'Test User',
        null, // avatarUrl
        'testuser',
        testDate,
        true, // isDiscoverable
      ]);
    });

    test('should support copyWith method', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        displayName: 'Test User',
        username: 'testuser',
        createdAt: testDate,
      );

      final updatedUser = user.copyWith(email: 'newemail@example.com');

      expect(updatedUser.email, equals('newemail@example.com'));
      expect(updatedUser.id, equals(user.id));
      expect(updatedUser.displayName, equals(user.displayName));
    });

    test('should handle null optional fields', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        username: 'testuser',
        createdAt: testDate,
      );

      expect(user.displayName, isNull);
      expect(user.avatarUrl, isNull);
    });

    test('should handle avatarUrl field', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        username: 'testuser',
        avatarUrl: 'https://example.com/avatar.jpg',
        createdAt: testDate,
      );

      expect(user.avatarUrl, 'https://example.com/avatar.jpg');
    });

    test('should handle isDiscoverable field', () {
      final user1 = User(
        id: 'user-123',
        email: 'test@example.com',
        username: 'testuser',
        createdAt: testDate,
        isDiscoverable: false,
      );

      final user2 = User(
        id: 'user-456',
        email: 'test2@example.com',
        username: 'testuser2',
        createdAt: testDate,
      );

      expect(user1.isDiscoverable, false);
      expect(user2.isDiscoverable, true); // default
    });

    test('should distinguish between different users', () {
      final user1 = User(
        id: 'user-1',
        email: 'test1@example.com',
        username: 'user1',
        createdAt: testDate,
      );

      final user2 = User(
        id: 'user-2',
        email: 'test2@example.com',
        username: 'user2',
        createdAt: testDate,
      );

      expect(user1, isNot(equals(user2)));
    });

    test('should support clearDisplayName in copyWith', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        displayName: 'Test User',
        username: 'testuser',
        createdAt: testDate,
      );

      final updatedUser = user.copyWith(clearDisplayName: true);

      expect(updatedUser.displayName, isNull);
      expect(user.displayName, 'Test User'); // original unchanged
    });

    test('should support clearAvatarUrl in copyWith', () {
      final user = User(
        id: 'user-123',
        email: 'test@example.com',
        username: 'testuser',
        avatarUrl: 'https://example.com/avatar.jpg',
        createdAt: testDate,
      );

      final updatedUser = user.copyWith(clearAvatarUrl: true);

      expect(updatedUser.avatarUrl, isNull);
      expect(user.avatarUrl, 'https://example.com/avatar.jpg');
    });
  });
}
