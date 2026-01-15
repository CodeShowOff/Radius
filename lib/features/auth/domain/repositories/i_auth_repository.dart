import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/user.dart';

/// Repository interface for authentication operations.
///
/// Defines the contract for auth data access.
/// Implementation details are in the data layer.
abstract class IAuthRepository {
  /// Returns a stream of the current authentication state.
  Stream<User?> get authStateChanges;

  /// Gets the currently authenticated user, if any.
  Future<Either<Failure, User?>> getCurrentUser();

  /// Signs in with email and password.
  Future<Either<Failure, User>> signInWithEmail({
    required String email,
    required String password,
  });

  /// Signs in with Google.
  Future<Either<Failure, User>> signInWithGoogle();

  /// Registers a new user with email and password.
  Future<Either<Failure, User>> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  /// Signs out the current user.
  Future<Either<Failure, void>> signOut();

  /// Sends a password reset email.
  Future<Either<Failure, void>> sendPasswordResetEmail(String email);
}
