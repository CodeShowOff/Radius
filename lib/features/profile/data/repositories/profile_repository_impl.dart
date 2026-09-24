import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/services/firebase/profile_service.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/i_profile_repository.dart';
import '../models/profile_model.dart';

/// Implementation of IProfileRepository using Firebase.
class ProfileRepositoryImpl implements IProfileRepository {
  final ProfileService _profileService;

  ProfileRepositoryImpl({required ProfileService profileService})
      : _profileService = profileService;

  @override
  Future<Either<Failure, Profile?>> getProfile(String userId) async {
    try {
      final profileModel = await _profileService.getProfile(userId);
      return Right(profileModel?.toEntity());
    } on ProfileServiceException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveProfile(Profile profile) async {
    try {
      final profileModel = ProfileModel.fromEntity(profile);
      final exists = await _profileService.profileExists(profile.userId);

      if (exists) {
        // Use toUpdateMap to exclude immutable fields (createdAt)
        // This prevents Firestore rule violations when updating
        await _profileService.updateProfile(
          profile.userId,
          ProfileModel.toUpdateMap(
            name: profile.name,
            bio: profile.bio,
            photoUrl: profile.photoUrl,
            isVisible: profile.isVisible,
            showOnlineStatus: profile.showOnlineStatus,
            allowConnectionRequests: profile.allowConnectionRequests,
            showLastSeen: profile.showLastSeen,
            vibe: profile.vibe,
            mood: profile.mood,
            gender: profile.gender,
            discoveryUsername: profile.discoveryUsername,
          ),
        );
      } else {
        await _profileService.createProfile(profileModel);
      }

      // Sync displayName to Firebase Auth so it stays consistent
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.displayName != profile.name) {
          await user.updateDisplayName(profile.name);
        }
      } catch (_) {
        // Best-effort â€” don't fail profile save if Auth sync fails
      }

      return const Right(null);
    } on ProfileServiceException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateProfile({
    required String userId,
    String? name,
    String? bio,
    String? photoUrl,
    bool? isVisible,
    String? vibe,
    String? mood,
    String? gender,
  }) async {
    try {
      final updateMap = ProfileModel.toUpdateMap(
        name: name,
        bio: bio,
        photoUrl: photoUrl,
        isVisible: isVisible,
        vibe: vibe,
        mood: mood,
        gender: gender,
      );

      await _profileService.updateProfile(userId, updateMap);
      return const Right(null);
    } on ProfileServiceException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateVisibility(
    String userId,
    bool isVisible,
  ) async {
    try {
      await _profileService.updateVisibility(userId, isVisible);
      return const Right(null);
    } on ProfileServiceException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Unexpected error: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteProfile(String userId) async {
    try {
      await _profileService.deleteProfile(userId);
      return const Right(null);
    } on ProfileServiceException catch (e) {
      return Left(ServerFailure(message: e.message));
    } catch (e) {
      return Left(ServerFailure(message: 'Unexpected error: $e'));
    }
  }

  @override
  Stream<Profile?> profileStream(String userId) {
    return _profileService
        .profileStream(userId)
        .map((model) => model?.toEntity());
  }
}
