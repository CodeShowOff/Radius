import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/profile/domain/entities/profile.dart';

void main() {
  group('Profile Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid Profile instance', () {
      final profile = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        bio: 'Test bio',
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(profile.id, 'profile-123');
      expect(profile.userId, 'user-123');
      expect(profile.name, 'John Doe');
      expect(profile.bio, 'Test bio');
    });

    test('should support value equality', () {
      final profile1 = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        createdAt: testDate,
        updatedAt: testDate,
      );

      final profile2 = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(profile1, equals(profile2));
    });

    test('should not be equal when properties differ', () {
      final profile1 = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        createdAt: testDate,
        updatedAt: testDate,
      );

      final profile2 = Profile(
        id: 'profile-456',
        userId: 'user-456',
        name: 'Jane Doe',
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(profile1, isNot(equals(profile2)));
    });

    test('should handle optional fields', () {
      final profile = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(profile.bio, '');
      expect(profile.photoUrl, isNull);
      expect(profile.vibe, isNull);
      expect(profile.mood, isNull);
    });

    test('copyWith should create a new instance with updated fields', () {
      final profile = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        bio: 'Old bio',
        createdAt: testDate,
        updatedAt: testDate,
      );

      final updatedProfile = profile.copyWith(
        name: 'Jane Doe',
        bio: 'New bio',
      );

      expect(updatedProfile.id, profile.id);
      expect(updatedProfile.name, 'Jane Doe');
      expect(updatedProfile.bio, 'New bio');
    });

    test('should handle vibe and mood fields', () {
      final profile = Profile(
        id: 'profile-123',
        userId: 'user-123',
        name: 'John Doe',
        vibe: 'Chill',
        mood: 'Happy',
        createdAt: testDate,
        updatedAt: testDate,
      );

      expect(profile.vibe, 'Chill');
      expect(profile.mood, 'Happy');
    });
  });
}
