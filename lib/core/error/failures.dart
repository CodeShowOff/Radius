import 'package:equatable/equatable.dart';

/// Base class for all failures in the application.
///
/// Provides a consistent way to handle errors across layers.
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({
    required this.message,
    this.code,
  });

  @override
  List<Object?> get props => [message, code];
}

/// Authentication-related failures
class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});

  factory AuthFailure.invalidCredentials() => const AuthFailure(
        message: 'Invalid email or password',
        code: 'invalid-credentials',
      );

  factory AuthFailure.userNotFound() => const AuthFailure(
        message: 'No user found with this email',
        code: 'user-not-found',
      );

  factory AuthFailure.emailAlreadyInUse() => const AuthFailure(
        message: 'An account already exists with this email',
        code: 'email-already-in-use',
      );

  factory AuthFailure.weakPassword() => const AuthFailure(
        message: 'Password is too weak',
        code: 'weak-password',
      );
}

/// Network-related failures
class NetworkFailure extends Failure {
  const NetworkFailure({required super.message, super.code});

  factory NetworkFailure.noConnection() => const NetworkFailure(
        message: 'No internet connection',
        code: 'no-connection',
      );

  factory NetworkFailure.timeout() => const NetworkFailure(
        message: 'Connection timed out',
        code: 'timeout',
      );
}

/// Bluetooth-related failures
class BluetoothFailure extends Failure {
  const BluetoothFailure({required super.message, super.code});

  factory BluetoothFailure.disabled() => const BluetoothFailure(
        message: 'Bluetooth is disabled',
        code: 'bluetooth-disabled',
      );

  factory BluetoothFailure.permissionDenied() => const BluetoothFailure(
        message: 'Bluetooth permission denied',
        code: 'permission-denied',
      );

  factory BluetoothFailure.scanFailed() => const BluetoothFailure(
        message: 'Failed to scan for nearby devices',
        code: 'scan-failed',
      );

  factory BluetoothFailure.advertiseFailed() => const BluetoothFailure(
        message: 'Failed to advertise device',
        code: 'advertise-failed',
      );
}

/// Database-related failures
class DatabaseFailure extends Failure {
  const DatabaseFailure({required super.message, super.code});

  factory DatabaseFailure.notFound() => const DatabaseFailure(
        message: 'Requested data not found',
        code: 'not-found',
      );

  factory DatabaseFailure.permissionDenied() => const DatabaseFailure(
        message: 'Permission denied to access data',
        code: 'permission-denied',
      );
}

/// Cache-related failures
class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});

  factory CacheFailure.notFound() => const CacheFailure(
        message: 'Cached data not found',
        code: 'cache-not-found',
      );
}

/// Server-related failures
class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

/// Unexpected failures
class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    super.message = 'An unexpected error occurred',
    super.code,
  });
}
