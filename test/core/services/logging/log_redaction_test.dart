import 'package:flutter_test/flutter_test.dart';
import 'package:radius/core/services/logging/log_redaction.dart';

void main() {
  group('LogRedaction - Sensitive Keys', () {
    test('should identify BLE-related sensitive keys', () {
      expect(LogRedaction.isSensitiveKey('bleId'), true);
      expect(LogRedaction.isSensitiveKey('anonymousId'), true);
      expect(LogRedaction.isSensitiveKey('deviceAddress'), true);
      expect(LogRedaction.isSensitiveKey('macAddress'), true);
      expect(LogRedaction.isSensitiveKey('manufacturerData'), true);
    });

    test('should identify FCM token keys as sensitive', () {
      expect(LogRedaction.isSensitiveKey('fcmToken'), true);
      expect(LogRedaction.isSensitiveKey('fcm_token'), true);
      expect(LogRedaction.isSensitiveKey('fcmTokens'), true);
      expect(LogRedaction.isSensitiveKey('pushToken'), true);
      expect(LogRedaction.isSensitiveKey('notificationToken'), true);
    });

    test('should identify user ID keys as sensitive', () {
      expect(LogRedaction.isSensitiveKey('userId'), true);
      expect(LogRedaction.isSensitiveKey('user_id'), true);
      expect(LogRedaction.isSensitiveKey('uid'), true);
      expect(LogRedaction.isSensitiveKey('senderId'), true);
      expect(LogRedaction.isSensitiveKey('recipientId'), true);
      expect(LogRedaction.isSensitiveKey('seekerId'), true);
      expect(LogRedaction.isSensitiveKey('helperId'), true);
      expect(LogRedaction.isSensitiveKey('memberId'), true);
      expect(LogRedaction.isSensitiveKey('ownerId'), true);
    });

    test('should identify email keys as sensitive', () {
      expect(LogRedaction.isSensitiveKey('email'), true);
      expect(LogRedaction.isSensitiveKey('emailAddress'), true);
      expect(LogRedaction.isSensitiveKey('userEmail'), true);
    });

    test('should identify GPS coordinate keys as sensitive', () {
      expect(LogRedaction.isSensitiveKey('latitude'), true);
      expect(LogRedaction.isSensitiveKey('longitude'), true);
      expect(LogRedaction.isSensitiveKey('lat'), true);
      expect(LogRedaction.isSensitiveKey('lng'), true);
      expect(LogRedaction.isSensitiveKey('gps'), true);
      expect(LogRedaction.isSensitiveKey('coordinates'), true);
      expect(LogRedaction.isSensitiveKey('geoHash'), true);
      expect(LogRedaction.isSensitiveKey('location'), true);
    });

    test('should allow BLE token keys (non-reversible)', () {
      expect(LogRedaction.isSensitiveKey('bleToken'), false);
      expect(LogRedaction.isSensitiveKey('ble_token'), false);
    });

    test('should not flag non-sensitive keys', () {
      expect(LogRedaction.isSensitiveKey('name'), false);
      expect(LogRedaction.isSensitiveKey('timestamp'), false);
      expect(LogRedaction.isSensitiveKey('message'), false);
      expect(LogRedaction.isSensitiveKey('status'), false);
    });
  });

  group('LogRedaction - String Redaction', () {
    test('should redact email addresses in strings', () {
      const input = 'User email is test@example.com for verification';
      final result = LogRedaction.redactString(input);
      expect(result, contains('<redacted_email>'));
      expect(result, isNot(contains('test@example.com')));
    });

    test('should redact multiple email addresses', () {
      const input = 'Contact user1@test.com or admin@example.org';
      final result = LogRedaction.redactString(input);
      expect(result, isNot(contains('user1@test.com')));
      expect(result, isNot(contains('admin@example.org')));
    });

    test('should redact key=value patterns for sensitive keys', () {
      const input = 'userId=abc123, fcmToken=xyz789';
      final result = LogRedaction.redactString(input);
      expect(result, contains('userId=<redacted>'));
      expect(result, contains('fcmToken=<redacted>'));
      expect(result, isNot(contains('abc123')));
      expect(result, isNot(contains('xyz789')));
    });

    test('should redact JSON patterns for sensitive keys', () {
      const input = '{"userId": "user123", "email": "test@test.com"}';
      final result = LogRedaction.redactString(input);
      expect(result, contains('"userId": "<redacted>"'));
      expect(result, contains('"email": "<redacted>"'));
      expect(result, isNot(contains('user123')));
    });

    test('should redact GPS coordinates in context', () {
      const input = 'User location: lat=37.7749, lng=-122.4194';
      final result = LogRedaction.redactString(input);
      expect(result, contains('lat=<redacted>'));
      expect(result, contains('lng=<redacted>'));
    });

    test('should redact coordinate pairs when in location context', () {
      const input = 'GPS position: (37.7749, -122.4194)';
      final result = LogRedaction.redactString(input);
      expect(result, contains('<redacted_coords>'));
      expect(result, isNot(contains('37.7749')));
    });

    test('should not redact coordinates outside location context', () {
      // This avoids over-redaction of non-GPS number pairs
      const input = 'Array values: (10, 20)';
      final result = LogRedaction.redactString(input);
      // Should NOT redact because no location context
      expect(result, equals(input));
    });
  });

  group('LogRedaction - Map Redaction', () {
    test('should redact sensitive values in maps', () {
      final data = {
        'userId': 'user123',
        'name': 'John Doe',
        'email': 'john@example.com',
        'fcmToken': 'token_xyz',
      };

      final result = LogRedaction.redactMap(data);
      expect(result!['userId'], equals('<redacted>'));
      expect(result['name'], equals('John Doe')); // Not sensitive
      expect(result['email'], equals('<redacted>'));
      expect(result['fcmToken'], equals('<redacted>'));
    });

    test('should redact GPS coordinates in maps', () {
      final data = {
        'latitude': 37.7749,
        'longitude': -122.4194,
        'timestamp': 1234567890,
      };

      final result = LogRedaction.redactMap(data);
      expect(result!['latitude'], equals('<redacted>'));
      expect(result['longitude'], equals('<redacted>'));
      expect(result['timestamp'], equals(1234567890)); // Not sensitive
    });

    test('should recursively redact nested maps', () {
      final data = {
        'user': {
          'userId': 'user123',
          'email': 'test@test.com',
          'profile': {
            'name': 'Test User',
            'memberId': 'member456',
          },
        },
      };

      final result = LogRedaction.redactMap(data);
      final user = result!['user'] as Map<String, Object?>;
      expect(user['userId'], equals('<redacted>'));
      expect(user['email'], equals('<redacted>'));

      final profile = user['profile'] as Map<String, Object?>;
      expect(profile['name'], equals('Test User'));
      expect(profile['memberId'], equals('<redacted>'));
    });

    test('should redact values in lists', () {
      final data = {
        'userIds': ['user1', 'user2', 'user3'],
        'names': ['Alice', 'Bob'],
      };

      final result = LogRedaction.redactMap(data);
      // When the key itself is sensitive, the whole value gets redacted
      expect(result!['userIds'], equals('<redacted 3 items>'));

      // Names list is not sensitive by key match, so it's preserved
      final names = result['names'] as List;
      expect(names.length, equals(2));
      expect(names, contains('Alice'));
      expect(names, contains('Bob'));
    });

    test('should handle BLE-related sensitive data', () {
      final data = {
        'bleId': 'abc123',
        'macAddress': '00:11:22:33:44:55',
        'manufacturerData': [1, 2, 3, 4],
        'bleToken': 'derived_token_ok',
      };

      final result = LogRedaction.redactMap(data);
      expect(result!['bleId'], equals('<redacted>'));
      expect(result['macAddress'], equals('<redacted>'));
      expect(result['manufacturerData'], equals('<redacted 4 items>'));
      expect(result['bleToken'], equals('derived_token_ok')); // Allowed
    });
  });

  group('LogRedaction - Edge Cases', () {
    test('should handle null and empty maps', () {
      expect(LogRedaction.redactMap(null), isNull);
      expect(LogRedaction.redactMap({}), isEmpty);
    });

    test('should handle null values in maps', () {
      final data = {'userId': null, 'name': null};
      final result = LogRedaction.redactMap(data);
      expect(result!['userId'], equals('<redacted>'));
      expect(result['name'], isNull);
    });

    test('should handle case-insensitive key matching', () {
      final data = {
        'UserId': 'user123',
        'EMAIL': 'test@test.com',
        'FcmToken': 'token',
      };

      final result = LogRedaction.redactMap(data);
      expect(result!['UserId'], equals('<redacted>'));
      expect(result['EMAIL'], equals('<redacted>'));
      expect(result['FcmToken'], equals('<redacted>'));
    });

    test('should redact FCM tokens with underscores and variations', () {
      expect(LogRedaction.isSensitiveKey('fcm_token'), true);
      expect(LogRedaction.isSensitiveKey('FCM_TOKEN'), true);
      expect(LogRedaction.isSensitiveKey('messagingToken'), true);
    });

    test('should redact compound user ID keys', () {
      expect(LogRedaction.isSensitiveKey('userId1'), true);
      expect(LogRedaction.isSensitiveKey('userId2'), true);
      expect(LogRedaction.isSensitiveKey('user_id_1'), true);
      expect(LogRedaction.isSensitiveKey('user_id_2'), true);
    });
  });
}
