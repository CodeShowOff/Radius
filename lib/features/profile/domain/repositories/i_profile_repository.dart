import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/profile.dart';

/// Abstract repository interface for profile operations.
abstract class IProfileRepository {
  /// Gets a profile by user ID.
  Future<Either<Failure, Profile?>> getProfile(String userId);

  /// Creates or updates a profile.
  Future<Either<Failure, void>> saveProfile(Profile profile);

  /// Updates specific profile fields.
  Future<Either<Failure, void>> updateProfile({
    required String userId,
    String? name,
    String? bio,
    String? photoUrl,
    bool? isVisible,
    String? vibe,
    String? mood,
    String? gender,
  });

  /// Updates profile visibility.
  Future<Either<Failure, void>> updateVisibility(String userId, bool isVisible);

  /// Deletes a profile.
  Future<Either<Failure, void>> deleteProfile(String userId);

  /// Streams real-time profile updates.
  Stream<Profile?> profileStream(String userId);
}
