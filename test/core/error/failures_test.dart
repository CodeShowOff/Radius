import 'package:flutter_test/flutter_test.dart';
import 'package:radius/core/error/failures.dart';

void main() {
  group('Failures', () {
    group('ServerFailure', () {
      test('should create ServerFailure with message', () {
        const failure = ServerFailure(message: 'Server error occurred');
        expect(failure.message, 'Server error occurred');
      });

      test('should support equality', () {
        const failure1 = ServerFailure(message: 'Error');
        const failure2 = ServerFailure(message: 'Error');
        const failure3 = ServerFailure(message: 'Different');

        expect(failure1, equals(failure2));
        expect(failure1, isNot(equals(failure3)));
      });

      test('should have correct props', () {
        const failure = ServerFailure(message: 'Error');
        expect(failure.props, ['Error', null]);
      });
    });

    group('NetworkFailure', () {
      test('should create NetworkFailure with message', () {
        const failure = NetworkFailure(message: 'No internet connection');
        expect(failure.message, 'No internet connection');
      });

      test('should support equality', () {
        const failure1 = NetworkFailure(message: 'No connection');
        const failure2 = NetworkFailure(message: 'No connection');

        expect(failure1, equals(failure2));
      });

      test('should have factory methods', () {
        final noConnection = NetworkFailure.noConnection();
        final timeout = NetworkFailure.timeout();

        expect(noConnection.message, 'No internet connection');
        expect(timeout.message, 'Connection timed out');
      });
    });

    group('CacheFailure', () {
      test('should create CacheFailure with message', () {
        const failure = CacheFailure(message: 'Cache read failed');
        expect(failure.message, 'Cache read failed');
      });

      test('should support equality', () {
        const failure1 = CacheFailure(message: 'Cache error');
        const failure2 = CacheFailure(message: 'Cache error');

        expect(failure1, equals(failure2));
      });

      test('should have factory method', () {
        final notFound = CacheFailure.notFound();
        expect(notFound.message, 'Cached data not found');
      });
    });

    group('AuthFailure', () {
      test('should create AuthFailure with message', () {
        const failure = AuthFailure(message: 'Invalid credentials');
        expect(failure.message, 'Invalid credentials');
      });

      test('should support equality', () {
        const failure1 = AuthFailure(message: 'Auth error');
        const failure2 = AuthFailure(message: 'Auth error');

        expect(failure1, equals(failure2));
      });

      test('should have factory methods', () {
        final invalidCreds = AuthFailure.invalidCredentials();
        final userNotFound = AuthFailure.userNotFound();
        final emailInUse = AuthFailure.emailAlreadyInUse();
        final weakPass = AuthFailure.weakPassword();

        expect(invalidCreds.message, 'Invalid email or password');
        expect(userNotFound.message, 'No user found with this email');
        expect(emailInUse.message, 'An account already exists with this email');
        expect(weakPass.message, 'Password is too weak');
      });
    });

    group('BluetoothFailure', () {
      test('should create BluetoothFailure with message', () {
        const failure = BluetoothFailure(message: 'Bluetooth error');
        expect(failure.message, 'Bluetooth error');
      });

      test('should have factory methods', () {
        final disabled = BluetoothFailure.disabled();
        final permissionDenied = BluetoothFailure.permissionDenied();
        final scanFailed = BluetoothFailure.scanFailed();
        final advertiseFailed = BluetoothFailure.advertiseFailed();

        expect(disabled.message, 'Bluetooth is disabled');
        expect(permissionDenied.message, 'Bluetooth permission denied');
        expect(scanFailed.message, 'Failed to scan for nearby devices');
        expect(advertiseFailed.message, 'Failed to advertise device');
      });
    });

    group('DatabaseFailure', () {
      test('should create DatabaseFailure with message', () {
        const failure = DatabaseFailure(message: 'Database error');
        expect(failure.message, 'Database error');
      });

      test('should have factory methods', () {
        final notFound = DatabaseFailure.notFound();
        final permissionDenied = DatabaseFailure.permissionDenied();

        expect(notFound.message, 'Requested data not found');
        expect(permissionDenied.message, 'Permission denied to access data');
      });
    });

    test('different failure types should not be equal', () {
      const serverFailure = ServerFailure(message: 'Error');
      const networkFailure = NetworkFailure(message: 'Error');
      const cacheFailure = CacheFailure(message: 'Error');

      expect(serverFailure, isNot(equals(networkFailure)));
      expect(networkFailure, isNot(equals(cacheFailure)));
      expect(cacheFailure, isNot(equals(serverFailure)));
    });
  });
}
