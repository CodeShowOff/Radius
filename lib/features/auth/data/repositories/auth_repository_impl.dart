import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/firebase/firebase_auth_service.dart';
import '../../../../core/services/firebase/firestore_service.dart';
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
  final Uuid _uuid;

  AuthRepositoryImpl({
    required FirebaseAuthService authService,
    required FirestoreService firestoreService,
    Uuid? uuid,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        _uuid = uuid ?? const Uuid();

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
      } catch (_) {
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
        return _createUserProfile(firebaseUser.uid, email, firebaseUser.displayName);
      }

      return Right(UserModel.fromFirestore(doc).toEntity());
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
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

  /// Creates a new user profile in Firestore.
  Future<Either<Failure, User>> _createUserProfile(
    String uid,
    String email,
    String? displayName, {
    String? avatarUrl,
  }) async {
    try {
      // Generate unique BLE identifier for this user
      final bleIdentifier = _uuid.v4();

      final userModel = UserModel(
        id: uid,
        email: email,
        displayName: displayName,
        avatarUrl: avatarUrl,
        bleIdentifier: bleIdentifier,
        createdAt: DateTime.now(),
        isDiscoverable: true,
      );

      await _firestoreService.setDocument(
        path: '${FirestoreCollections.users}/$uid',
        data: userModel.toFirestore(),
        merge: false,
      );

      return Right(userModel.toEntity());
    } on DatabaseException catch (e) {
      return Left(DatabaseFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }
}
