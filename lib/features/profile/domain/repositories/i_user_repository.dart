import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../auth/domain/entities/user.dart';

/// Repository interface for user profile operations.
abstract class IUserRepository {
  /// Get user profile by ID.
  Future<Either<Failure, User>> getUserById(String userId);
  
  /// Get user profile by BLE identifier.
  Future<Either<Failure, User>> getUserByBleId(String bleIdentifier);
  
  /// Update current user's profile.
  Future<Either<Failure, User>> updateProfile({
    String? displayName,
    String? avatarUrl,
    bool? isDiscoverable,
  });
  
  /// Stream of current user's profile changes.
  Stream<User?> get userProfileStream;
  
  /// Get multiple users by IDs (batch fetch).
  Future<Either<Failure, List<User>>> getUsersByIds(List<String> userIds);
}
