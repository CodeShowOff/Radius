import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/firebase/firebase_auth_service.dart';
import '../../../../core/services/firebase/firestore_service.dart';
import '../../../../core/services/firebase/profile_service.dart';
import '../../../../core/services/firebase/username_service.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../models/user_model.dart';

/// Implementation of [IAuthRepository] using Firebase services.
///
/// Handles authentication logic and user profile creation in Firestore.
@LazySingleton(as: IAuthRepository)
class AuthRepositoryImpl implements IAuthRepository {
  final FirebaseAuthService _authService;
  final FirestoreService _firestoreService;
  final UsernameService _usernameService;
  final ProfileService _profileService;

  AuthRepositoryImpl({
    required FirebaseAuthService authService,
    required FirestoreService firestoreService,
    required ProfileService profileService,
    UsernameService? usernameService,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        _profileService = profileService,
        _usernameService = usernameService ?? UsernameService();

  @override
  Stream<User?> get authStateChanges {
    return _authService.authStateChanges.asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;

      try {
        // Fetch user profile from Firestore
        final doc = await _firestoreService.getDocument(
          '${FirestoreCollections.users}/${firebaseUser.uid}',
        );

        if (doc == null) return null;

        return UserModel.fromFirestore(doc).toEntity();
      } on ArgumentError {
        // Invalid document structure - treat as no user profile
        return null;
      } on DatabaseException {
        // Database error - treat as no user profile available
        return null;
      } catch (e) {
        // Unexpected error - log for debugging but don't crash
        // In production, this should be logged to crash reporting
        assert(() {
          // ignore: avoid_print
          print('AuthRepository.authStateChanges unexpected error: $e');
          return true;
        }());
        return null;
      }
    });
  }

  @override
  Future<Either<Failure, User?>> getCurrentUser() async {
    try {
      final firebaseUser = _authService.currentUser;
      if (firebaseUser == null) {
        return const Right(null);
      }

      final doc = await _firestoreService.getDocument(
        '${FirestoreCollections.users}/${firebaseUser.uid}',
      );

      if (doc == null) {
        return const Right(null);
      }

      return Right(UserModel.fromFirestore(doc).toEntity());
    } on ArgumentError catch (e) {
      // Invalid document structure in Firestore
      return Left(DatabaseFailure(
        message: 'Invalid user profile data: ${e.message}',
        code: 'invalid-data',
      ));
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final firebaseUser = await _authService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Fetch user profile from Firestore
      final doc = await _firestoreService.getDocument(
        '${FirestoreCollections.users}/${firebaseUser.uid}',
      );

      if (doc == null) {
        // User exists in Auth but not in Firestore - create profile
        return _createUserProfile(
            firebaseUser.uid, email, firebaseUser.displayName);
      }

      return Right(UserModel.fromFirestore(doc).toEntity());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } on ArgumentError catch (e) {
      return Left(DatabaseFailure(
        message: 'Invalid user profile data: ${e.message}',
        code: 'invalid-data',
      ));
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> signInWithGoogle() async {
    try {
      final firebaseUser = await _authService.signInWithGoogle();

      // Check if user profile exists in Firestore
      final doc = await _firestoreService.getDocument(
        '${FirestoreCollections.users}/${firebaseUser.uid}',
      );

      if (doc == null) {
        // First time Google sign-in - create profile
        return _createUserProfile(
          firebaseUser.uid,
          firebaseUser.email ?? '',
          firebaseUser.displayName,
          avatarUrl: firebaseUser.photoURL,
        );
      }

      return Right(UserModel.fromFirestore(doc).toEntity());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } on ArgumentError catch (e) {
      return Left(DatabaseFailure(
        message: 'Invalid user profile data: ${e.message}',
        code: 'invalid-data',
      ));
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, User>> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final firebaseUser = await _authService.createUserWithEmailAndPassword(
        email: email,
        password: password,
        displayName: displayName,
      );

      // Send verification email
      await _authService.sendEmailVerification();

      // Create user profile in Firestore
      return _createUserProfile(
        firebaseUser.uid,
        email,
        displayName,
      );
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await _authService.signOut();
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> sendPasswordResetEmail(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> sendEmailVerification() async {
    try {
      await _authService.sendEmailVerification();
      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  Future<Either<Failure, bool>> checkEmailVerified() async {
    try {
      await _authService.reloadUser();
      return Right(_authService.isEmailVerified);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  @override
  bool get isEmailVerified => _authService.isEmailVerified;

  @override
  Future<Either<Failure, void>> deleteAccount() async {
    try {
      final uid = _authService.currentUser?.uid;
      if (uid == null) {
        return const Left(AuthFailure(
          message: 'No user signed in',
          code: 'no-user',
        ));
      }

      // Delete user data from Firestore first
      try {
        // Get username before deleting user document
        String? username;
        try {
          final userDoc = await _firestoreService.getDocument(
            '${FirestoreCollections.users}/$uid',
          );
          if (userDoc != null && userDoc['username'] != null) {
            username = userDoc['username'] as String;
          }
        } catch (e) {
          // Continue even if we can't get username
        }

        // Delete profile
        await _profileService.deleteProfile(uid);

        // Delete user document
        await _firestoreService.deleteDocument(
          '${FirestoreCollections.users}/$uid',
        );

        // Delete username index if we found the username
        if (username != null) {
          try {
            await _firestoreService.deleteDocument(
              'username_index/$username',
            );
          } catch (e) {
            // Username index might already be deleted, continue
          }
        }
      } catch (e) {
        // Log but continue with account deletion
        // ignore: avoid_print
        print('Warning: Failed to delete user data: $e');
      }

      // Delete Firebase Auth account
      await _authService.deleteAccount();

      return const Right(null);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  /// Creates a new user profile in Firestore.
  Future<Either<Failure, User>> _createUserProfile(
    String uid,
    String email,
    String? displayName, {
    String? avatarUrl,
  }) async {
    try {
      // Generate unique username using Firestore transaction
      final username = await _usernameService.generateUsername();

      final userModel = UserModel(
        id: uid,
        email: email,
        displayName: displayName,
        avatarUrl: avatarUrl,
        username: username,
        createdAt: null, // Will be set by server timestamp
        isDiscoverable: true,
      );

      // Use server timestamp for createdAt to satisfy Firestore rules
      await _firestoreService.setDocument(
        path: '${FirestoreCollections.users}/$uid',
        data: userModel.toFirestore(useServerTimestamp: true),
        merge: false,
      );

      // Store username-to-userId index for BLE discovery lookups
      await _usernameService.storeUsernameForUser(uid, username);

      // Create profile entry in profiles collection
      final now = DateTime.now();
      final profileModel = ProfileModel(
        id: uid,
        userId: uid,
        name: displayName ?? '',
        bio: '',
        photoUrl: avatarUrl,
        isVisible: true,
        showOnlineStatus: true,
        allowConnectionRequests: true,
        showLastSeen: true,
        createdAt: now,
        updatedAt: now,
      );

      try {
        await _profileService.createProfile(profileModel);
      } catch (e) {
        // Log but don't fail - profile can be created later
        // ignore: avoid_print
        print('Warning: Failed to create profile entry: $e');
      }

      // Read back the document to get the server-set timestamp
      final doc = await _firestoreService.getDocument(
        '${FirestoreCollections.users}/$uid',
      );

      if (doc == null) {
        return const Left(
            DatabaseFailure(message: 'Failed to create user profile'));
      }

      return Right(UserModel.fromFirestore(doc).toEntity());
    } on ArgumentError catch (e) {
      return Left(DatabaseFailure(
        message: 'Invalid user profile data: ${e.message}',
        code: 'invalid-data',
      ));
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }
}
