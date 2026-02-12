import 'package:flutter_test/flutter_test.dart';
import 'package:radius/core/services/bluetooth/ble_uuid_encoder.dart';

void main() {
  group('BleUuidEncoder', () {
    test('encodes and decodes username correctly', () {
      const username = 'aB3x9Yz';
      
      final uuid = BleUuidEncoder.encodeUsernameToUuid(username);
      expect(uuid, isNotNull);
      expect(uuid, startsWith('0000BEEF-'));
      
      final decoded = BleUuidEncoder.decodeUuidToUsername(uuid);
      expect(decoded, equals(username));
    });

    test('encodes different usernames to different UUIDs', () {
      const username1 = 'abc1234';
      const username2 = 'xyz9876';
      
      final uuid1 = BleUuidEncoder.encodeUsernameToUuid(username1);
      final uuid2 = BleUuidEncoder.encodeUsernameToUuid(username2);
      
      expect(uuid1, isNot(equals(uuid2)));
    });

    test('decodes UUID with lowercase correctly', () {
      const username = 'JohnDoe';
      
      final uuid = BleUuidEncoder.encodeUsernameToUuid(username);
      final lowercaseUuid = uuid.toLowerCase();
      
      final decoded = BleUuidEncoder.decodeUuidToUsername(lowercaseUuid);
      expect(decoded, equals(username));
    });

    test('rejects invalid username length', () {
      expect(() => BleUuidEncoder.encodeUsernameToUuid('short'), throwsArgumentError);
      expect(() => BleUuidEncoder.encodeUsernameToUuid('toolongusername'), throwsArgumentError);
    });

    test('rejects username with invalid characters', () {
      expect(() => BleUuidEncoder.encodeUsernameToUuid('abc_123'), throwsArgumentError);
      expect(() => BleUuidEncoder.encodeUsernameToUuid('abc-123'), throwsArgumentError);
      expect(() => BleUuidEncoder.encodeUsernameToUuid('abc 123'), throwsArgumentError);
    });

    test('validates username correctly', () {
      expect(BleUuidEncoder.isValidUsername('abc1234'), isTrue);
      expect(BleUuidEncoder.isValidUsername('XYZ9876'), isTrue);
      expect(BleUuidEncoder.isValidUsername('aBcDeF0'), isTrue);
      
      expect(BleUuidEncoder.isValidUsername('short'), isFalse);
      expect(BleUuidEncoder.isValidUsername('toolong1'), isFalse);
      expect(BleUuidEncoder.isValidUsername('abc_123'), isFalse);
      expect(BleUuidEncoder.isValidUsername('abc-123'), isFalse);
    });

    test('identifies Radius UUIDs correctly', () {
      const username = 'test123';
      final uuid = BleUuidEncoder.encodeUsernameToUuid(username);
      
      expect(BleUuidEncoder.isRadiusUuid(uuid), isTrue);
      expect(BleUuidEncoder.isRadiusUuid('0000FFFF-0000-1000-8000-00805F9B34FB'), isFalse);
      expect(BleUuidEncoder.isRadiusUuid('random-string'), isFalse);
    });

    test('returns null for invalid UUID format', () {
      expect(BleUuidEncoder.decodeUuidToUsername('invalid-uuid'), isNull);
      expect(BleUuidEncoder.decodeUuidToUsername('0000FFFF-0000-1000-8000-00805F9B34FB'), isNull);
    });

    test('encodes all character ranges correctly', () {
      // Test lowercase
      const lowercase = 'abcdefg';
      final uuid1 = BleUuidEncoder.encodeUsernameToUuid(lowercase);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid1), equals(lowercase));
      
      // Test uppercase
      const uppercase = 'ABCDEFG';
      final uuid2 = BleUuidEncoder.encodeUsernameToUuid(uppercase);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid2), equals(uppercase));
      
      // Test numbers
      const numbers = '1234567';
      final uuid3 = BleUuidEncoder.encodeUsernameToUuid(numbers);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid3), equals(numbers));
      
      // Test mixed
      const mixed = 'aB3Xy9Z';
      final uuid4 = BleUuidEncoder.encodeUsernameToUuid(mixed);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid4), equals(mixed));
    });

    test('handles edge case usernames', () {
      // All 'a's
      const allA = 'aaaaaaa';
      final uuid1 = BleUuidEncoder.encodeUsernameToUuid(allA);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid1), equals(allA));
      
      // All '9's
      const all9 = '9999999';
      final uuid2 = BleUuidEncoder.encodeUsernameToUuid(all9);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid2), equals(all9));
      
      // All 'Z's
      const allZ = 'ZZZZZZZ';
      final uuid3 = BleUuidEncoder.encodeUsernameToUuid(allZ);
      expect(BleUuidEncoder.decodeUuidToUsername(uuid3), equals(allZ));
    });

    test('UUID maintains Bluetooth Base UUID structure', () {
      const username = 'test123';
      final uuid = BleUuidEncoder.encodeUsernameToUuid(username);
      
      // Check that it follows the pattern: XXXXXXXX-XXXX-XXXX-8XXX-XXXXXXXXXXXX
      expect(uuid, matches(RegExp(r'^0000BEEF-[0-9A-F]{4}-[0-9A-F]{4}-8000-[0-9A-F]{12}$')));
    });
  });
}
