import 'package:flutter_test/flutter_test.dart';
import 'package:radius/core/device_session/domain/entities/device_session.dart';

void main() {
  group('DeviceSession Entity', () {
    final testDate = DateTime(2024, 1, 1);

    test('should create a valid DeviceSession instance', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
      );

      expect(session.sessionId, 'session-123');
      expect(session.userId, 'user-123');
      expect(session.timestamp, testDate);
      expect(session.sessionType, 'login');
    });

    test('should support value equality', () {
      final session1 = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
      );

      final session2 = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
      );

      expect(session1, equals(session2));
    });

    test('should handle device information', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        deviceBrand: 'Samsung',
        deviceModel: 'Galaxy S21',
        deviceType: 'phone',
        operatingSystem: 'Android',
        osVersion: '13',
        buildNumber: 'TP1A.220624.014',
      );

      expect(session.deviceBrand, 'Samsung');
      expect(session.deviceModel, 'Galaxy S21');
      expect(session.deviceType, 'phone');
      expect(session.operatingSystem, 'Android');
      expect(session.osVersion, '13');
      expect(session.buildNumber, 'TP1A.220624.014');
    });

    test('should handle screen information', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        screenResolution: '1080x2400',
        screenDensity: 2.75,
      );

      expect(session.screenResolution, '1080x2400');
      expect(session.screenDensity, 2.75);
    });

    test('should handle app information', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        appVersion: '1.0.0',
        appBuildNumber: '42',
        installSource: 'Play Store',
      );

      expect(session.appVersion, '1.0.0');
      expect(session.appBuildNumber, '42');
      expect(session.installSource, 'Play Store');
    });

    test('should handle network information', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        ipAddress: '192.168.1.1',
        country: 'United States',
        city: 'San Francisco',
        isp: 'Comcast',
        networkType: 'WiFi',
      );

      expect(session.ipAddress, '192.168.1.1');
      expect(session.country, 'United States');
      expect(session.city, 'San Francisco');
      expect(session.isp, 'Comcast');
      expect(session.networkType, 'WiFi');
    });

    test('should handle carrier information for cellular', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        networkType: 'cellular',
        carrierName: 'Verizon',
      );

      expect(session.networkType, 'cellular');
      expect(session.carrierName, 'Verizon');
    });

    test('should distinguish between login and register sessions', () {
      final loginSession = DeviceSession(
        sessionId: 'session-1',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
      );

      final registerSession = DeviceSession(
        sessionId: 'session-2',
        userId: 'user-456',
        timestamp: testDate,
        sessionType: 'register',
      );

      expect(loginSession.sessionType, 'login');
      expect(registerSession.sessionType, 'register');
    });

    test('should handle iOS device', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        deviceBrand: 'Apple',
        deviceModel: 'iPhone 14 Pro',
        deviceType: 'phone',
        operatingSystem: 'iOS',
        osVersion: '16.5',
        buildNumber: '20F66',
      );

      expect(session.deviceBrand, 'Apple');
      expect(session.deviceModel, 'iPhone 14 Pro');
      expect(session.operatingSystem, 'iOS');
      expect(session.osVersion, '16.5');
    });

    test('should handle Android device', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        deviceBrand: 'Google',
        deviceModel: 'Pixel 7',
        deviceType: 'phone',
        operatingSystem: 'Android',
        osVersion: '14',
      );

      expect(session.deviceBrand, 'Google');
      expect(session.deviceModel, 'Pixel 7');
      expect(session.operatingSystem, 'Android');
      expect(session.osVersion, '14');
    });

    test('should handle tablet device type', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        deviceType: 'tablet',
        deviceBrand: 'Samsung',
        deviceModel: 'Galaxy Tab S8',
      );

      expect(session.deviceType, 'tablet');
    });

    test('should handle emulator detection', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
        deviceType: 'emulator',
        deviceBrand: 'Google',
        deviceModel: 'Android SDK built for x86',
      );

      expect(session.deviceType, 'emulator');
    });

    test('should handle minimal session with only required fields', () {
      final session = DeviceSession(
        sessionId: 'session-123',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
      );

      expect(session.deviceBrand, isNull);
      expect(session.deviceModel, isNull);
      expect(session.operatingSystem, isNull);
      expect(session.ipAddress, isNull);
      expect(session.country, isNull);
    });

    test('should distinguish between different sessions', () {
      final session1 = DeviceSession(
        sessionId: 'session-1',
        userId: 'user-123',
        timestamp: testDate,
        sessionType: 'login',
      );

      final session2 = DeviceSession(
        sessionId: 'session-2',
        userId: 'user-123',
        timestamp: testDate.add(const Duration(hours: 1)),
        sessionType: 'login',
      );

      expect(session1, isNot(equals(session2)));
    });

  });
}
