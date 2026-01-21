import 'package:flutter_test/flutter_test.dart';
import 'package:radius/features/proximity/domain/entities/nearby_user.dart';

void main() {
  group('NearbyUser Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid NearbyUser instance', () {
      final user = NearbyUser(
        username: 'testuser',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      expect(user.username, 'testuser');
      expect(user.rssi, -65);
      expect(user.firstSeen, testDate);
      expect(user.lastSeen, testDate);
    });

    test('should support value equality', () {
      final user1 = NearbyUser(
        username: 'testuser',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final user2 = NearbyUser(
        username: 'testuser',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      expect(user1, equals(user2));
    });

    test('should calculate proximity from RSSI', () {
      final immediateUser = NearbyUser(
        username: 'user1',
        rssi: -45, // > -50
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final nearUser = NearbyUser(
        username: 'user2',
        rssi: -60, // -50 to -70
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final farUser = NearbyUser(
        username: 'user3',
        rssi: -75, // -70 to -85
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final veryFarUser = NearbyUser(
        username: 'user4',
        rssi: -90, // < -85
        firstSeen: testDate,
        lastSeen: testDate,
      );

      expect(immediateUser.proximity, BleProximity.immediate);
      expect(nearUser.proximity, BleProximity.near);
      expect(farUser.proximity, BleProximity.far);
      expect(veryFarUser.proximity, BleProximity.veryFar);
    });

    test('BleProximity.fromRssi should correctly determine proximity', () {
      expect(BleProximity.fromRssi(-40), BleProximity.immediate);
      expect(BleProximity.fromRssi(-60), BleProximity.near);
      expect(BleProximity.fromRssi(-75), BleProximity.far);
      expect(BleProximity.fromRssi(-90), BleProximity.veryFar);
      expect(BleProximity.fromRssi(0), BleProximity.unknown);
    });

    test('BleProximity should have correct display names', () {
      expect(BleProximity.immediate.displayName, 'Very close');
      expect(BleProximity.near.displayName, 'Nearby');
      expect(BleProximity.far.displayName, 'Far');
      expect(BleProximity.veryFar.displayName, 'Very far');
      expect(BleProximity.unknown.displayName, 'Unknown');
    });

    test('should handle optional profile fields', () {
      final userWithProfile = NearbyUser(
        username: 'testuser',
        userId: 'user-123',
        displayName: 'Test User',
        photoUrl: 'https://example.com/photo.jpg',
        bio: 'Hello there',
        vibe: 'Chill',
        mood: 'Happy',
        gender: 'Male',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      expect(userWithProfile.userId, 'user-123');
      expect(userWithProfile.displayName, 'Test User');
      expect(userWithProfile.photoUrl, 'https://example.com/photo.jpg');
      expect(userWithProfile.bio, 'Hello there');
      expect(userWithProfile.vibe, 'Chill');
      expect(userWithProfile.mood, 'Happy');
      expect(userWithProfile.gender, 'Male');
    });

    test('should handle connection status', () {
      final connectedUser = NearbyUser(
        username: 'testuser',
        rssi: -65,
        isConnected: true,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final notConnectedUser = NearbyUser(
        username: 'newuser',
        rssi: -65,
        isConnected: false,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      expect(connectedUser.isConnected, true);
      expect(notConnectedUser.isConnected, false);
    });

    test('should track first and last seen times', () {
      final firstSeenTime = testDate;
      final lastSeenTime = testDate.add(const Duration(minutes: 5));

      final user = NearbyUser(
        username: 'testuser',
        rssi: -65,
        firstSeen: firstSeenTime,
        lastSeen: lastSeenTime,
      );

      expect(user.firstSeen, firstSeenTime);
      expect(user.lastSeen, lastSeenTime);
      expect(user.lastSeen.isAfter(user.firstSeen), true);
    });

    test('should handle RSSI changes for same user', () {
      final user1 = NearbyUser(
        username: 'testuser',
        rssi: -50,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final user2 = NearbyUser(
        username: 'testuser',
        rssi: -80,
        firstSeen: testDate,
        lastSeen: testDate.add(const Duration(seconds: 5)),
      );

      expect(user1.proximity, BleProximity.near);
      expect(user2.proximity, BleProximity.far);
      expect(user1.username, user2.username); // same user
    });

    test('should distinguish between different users', () {
      final user1 = NearbyUser(
        username: 'user1',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final user2 = NearbyUser(
        username: 'user2',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      expect(user1, isNot(equals(user2)));
    });

    test('copyWith should create updated instance', () {
      final user = NearbyUser(
        username: 'testuser',
        rssi: -65,
        firstSeen: testDate,
        lastSeen: testDate,
      );

      final updatedUser = user.copyWith(
        rssi: -55,
        lastSeen: testDate.add(const Duration(seconds: 10)),
      );

      expect(updatedUser.rssi, -55);
      expect(updatedUser.lastSeen, testDate.add(const Duration(seconds: 10)));
      expect(updatedUser.username, 'testuser'); // unchanged
      expect(updatedUser.firstSeen, testDate); // unchanged
    });
  });
}
