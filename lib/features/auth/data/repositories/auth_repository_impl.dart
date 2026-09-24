import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:injectable/injectable.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/device_session/data/services/device_info_service.dart';
import '../../../../core/device_session/domain/repositories/i_device_session_repository.dart';
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
  final DeviceInfoService _deviceInfoService;
  final IDeviceSessionRepository _deviceSessionRepository;

  AuthRepositoryImpl({
    required FirebaseAuthService authService,
    required FirestoreService firestoreService,
    required ProfileService profileService,
    required DeviceInfoService deviceInfoService,
    required IDeviceSessionRepository deviceSessionRepository,
    UsernameService? usernameService,
  })  : _authService = authService,
        _firestoreService = firestoreService,
        _profileService = profileService,
        _deviceInfoService = deviceInfoService,
        _deviceSessionRepository = deviceSessionRepository,
        _usernameService = usernameService ?? UsernameService();

  @override
  Stream<User?> get authStateChanges {
    return _authService.authStateChanges.asyncMap((firebaseUser) async {
      if (firebaseUser == null) return null;

      try {
        // Use cache-first strategy to avoid a redundant network round-trip.
        // When the subscription starts, Firebase immediately emits the
        // current user. The AuthBloc already has this user from the initial
        // getCurrentUser() call, so the cache read is sufficient. Subsequent
        // stream events (sign-out, account deletion) either return null or
        // are handled by the network fallback.
        final docPath =
            '${FirestoreCollections.users}/${firebaseUser.uid}';
        Map<String, dynamic>? doc;

        try {
          final cachedSnap = await FirebaseFirestore.instance
              .doc(docPath)
              .get(const GetOptions(source: Source.cache));
          if (cachedSnap.exists && cachedSnap.data() != null) {
            doc = {'id': cachedSnap.id, ...cachedSnap.data()!};
          }
        } catch (_) {
          // Cache miss (first install, cleared data) â€” fall through to network.
        }

        // Fall back to network if no cached document.
        doc ??= await _firestoreService.getDocument(docPath);

        if (doc == null) return null;

        // Migration: Ensure profile exists in profiles collection for backward compatibility
        // This handles existing users who were created before the profiles collection sync was implemented
        _ensureProfileExists(firebaseUser.uid, doc);

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

      final docPath =
          '${FirestoreCollections.users}/${firebaseUser.uid}';

      // Try Firestore local cache first for instant startup.
      // Persistence is enabled so returning users will have their profile
      // document cached locally. This avoids the 300-1500 ms network
      // round-trip that previously blocked the splash screen.
      Map<String, dynamic>? doc;
      try {
        final cachedSnap = await FirebaseFirestore.instance
            .doc(docPath)
            .get(const GetOptions(source: Source.cache));
        if (cachedSnap.exists && cachedSnap.data() != null) {
          doc = {'id': cachedSnap.id, ...cachedSnap.data()!};
        }
      } catch (_) {
        // Cache miss (first install, cleared data) â€” fall through to network.
      }

      // Fall back to network if no cached document.
      doc ??= await _firestoreService.getDocument(docPath);

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
        // Force token refresh before creating profile
        await _authService.getIdToken(forceRefresh: true);
        
        return await _createUserProfileWithRetry(
            firebaseUser.uid, email, firebaseUser.displayName);
      }

      // Record device session for security and debugging
      _recordDeviceSession(firebaseUser.uid, 'login');

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

      // Force refresh the ID token to ensure it's fully propagated to Firestore
      await _authService.getIdToken(forceRefresh: true);

      // Use retry logic for the entire Firestore operation since both read and write
      // can fail with permission-denied during token propagation
      return await _handleGoogleSignInFirestoreOperations(firebaseUser);
    } on AuthException catch (e) {
      return Left(AuthFailure(message: e.message, code: e.code));
    } catch (e) {
      return Left(UnexpectedFailure(message: e.toString()));
    }
  }

  /// Handles the Firestore operations after Google sign-in with retry logic.
  /// Both reading and writing to Firestore can fail during token propagation.
  Future<Either<Failure, User>> _handleGoogleSignInFirestoreOperations(
    firebase_auth.User firebaseUser,
  ) async {
    const maxRetries = 4;
    const baseDelay = Duration(milliseconds: 300);
    
    Object? lastError;
    String? username; // Preserve username across retries to avoid generating duplicates
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Check if user profile exists in Firestore
        final doc = await _firestoreService.getDocument(
          '${FirestoreCollections.users}/${firebaseUser.uid}',
        );

        if (doc == null) {
          // First time Google sign-in - create profile directly within retry loop
          // Generate unique username only on first attempt
          username ??= await _usernameService.generateUsername();

          final userModel = UserModel(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName: firebaseUser.displayName,
            avatarUrl: firebaseUser.photoURL,
            username: username,
            createdAt: null,
            isDiscoverable: true,
          );

          // Create users doc with server timestamp
          await _firestoreService.setDocument(
            path: '${FirestoreCollections.users}/${firebaseUser.uid}',
            data: userModel.toFirestore(useServerTimestamp: true),
            merge: false,
          );

          // Store username index
          await _usernameService.storeUsernameForUser(
            firebaseUser.uid, 
            username,
          );

          // Create profile entry in profiles collection
          final now = DateTime.now();
          final profileModel = ProfileModel(
            id: firebaseUser.uid,
            userId: firebaseUser.uid,
            name: firebaseUser.displayName ?? '',
            bio: '',
            photoUrl: firebaseUser.photoURL,
            isVisible: true,
            showOnlineStatus: true,
            allowConnectionRequests: true,
            showLastSeen: true,
            createdAt: now,
            updatedAt: now,
          );

          // Create profile without additional retry since we're already in a retry loop
          await _profileService.createProfileDirect(profileModel);

          // Read back the document to get server timestamp
          final createdDoc = await _firestoreService.getDocument(
            '${FirestoreCollections.users}/${firebaseUser.uid}',
          );

          if (createdDoc == null) {
            throw Exception('Failed to read back created user profile');
          }

          _recordDeviceSession(firebaseUser.uid, 'register');
          return Right(UserModel.fromFirestore(createdDoc).toEntity());
        }

        // User already exists - update their profile info from Google
        await _profileService.updateProfile(
          firebaseUser.uid,
          ProfileModel.toUpdateMap(
            name: firebaseUser.displayName,
            photoUrl: firebaseUser.photoURL,
          ),
        );

        _recordDeviceSession(firebaseUser.uid, 'login');
        return Right(UserModel.fromFirestore(doc).toEntity());
        
      } on ArgumentError catch (e) {
        // Don't retry argument errors - they won't be fixed by retrying
        return Left(DatabaseFailure(
          message: 'Invalid user profile data: ${e.message}',
          code: 'invalid-data',
        ));
      } catch (e) {
        lastError = e;
        
        final errorString = e.toString().toLowerCase();
        final isPermissionError = errorString.contains('permission-denied') || 
                                  errorString.contains('permission_denied') ||
                                  errorString.contains('permission denied');
        final isLastAttempt = attempt == maxRetries - 1;
        
        if (isPermissionError && !isLastAttempt) {
          // Wait with exponential backoff before retrying
          final delay = baseDelay * (attempt + 1);
          await Future.delayed(delay);
          
          // Force refresh the token again before retry
          await _authService.getIdToken(forceRefresh: true);
          continue;
        }
        
        // For non-permission errors or if all retries exhausted, break out
        break;
      }
    }
    
    // All retries failed - return appropriate error
    if (lastError is DatabaseException) {
      return Left(DatabaseFailure(
        message: lastError.message,
        code: lastError.code,
      ));
    }
    
    return Left(UnexpectedFailure(
      message: lastError?.toString() ?? 'Google sign-in failed after retries',
    ));
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

      // Force token refresh before creating profile
      await _authService.getIdToken(forceRefresh: true);

      // Create user profile in Firestore with retry logic
      return await _createUserProfileWithRetry(
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
      // NOTE: Device session logout recording is handled by AuthBloc BEFORE
      // Firestore network is disabled. Do NOT record here â€” this method runs
      // after disableNetwork(), so Firestore writes would be queued and only
      // sent after enableNetwork(), by which time auth is already revoked.

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

      // Anonymize user data: keep documents but remove identifying info
      // so the user is no longer discoverable
      try {
        // Get username before clearing it
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

        // Anonymize profile: set display name to "Deleted Account",
        // clear username and discoveryUsername, mark as not discoverable/visible
        await _profileService.updateProfile(uid, {
          'name': 'Deleted Account',
          'displayName': 'Deleted Account',
          'username': '',
          'discoveryUsername': '',
          'isVisible': false,
          'isDiscoverable': false,
          'photoUrl': null,
          'bio': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Delete username index entry so the username is freed up
        if (username != null) {
          try {
            await _firestoreService.deleteDocument(
              'username_index/$username',
            );
          } catch (e) {
            // Log but continue â€” username index cleanup is best-effort
            assert(() {
              // ignore: avoid_print
              print('Warning: Failed to delete username index: $e');
              return true;
            }());
          }
        }
      } catch (e) {
        // Log but continue with auth account deletion
        assert(() {
          // ignore: avoid_print
          print('Warning: Failed to anonymize user data: $e');
          return true;
        }());
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

  /// Creates a new user profile with retry logic for handling auth token propagation delays.
  /// This is critical for first-time sign-ups where Firestore rules may reject
  /// writes before the auth token is fully propagated.
  Future<Either<Failure, User>> _createUserProfileWithRetry(
    String uid,
    String email,
    String? displayName, {
    String? photoUrl,
  }) async {
    const maxRetries = 4;
    const baseDelay = Duration(milliseconds: 300);
    
    Object? lastError;
    String? username;
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Generate unique username only on first attempt to avoid creating multiple usernames
        username ??= await _usernameService.generateUsername();

        final userModel = UserModel(
          id: uid,
          email: email,
          displayName: displayName,
          avatarUrl: photoUrl,
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
          photoUrl: photoUrl,
          isVisible: true,
          showOnlineStatus: true,
          allowConnectionRequests: true,
          showLastSeen: true,
          createdAt: now,
          updatedAt: now,
        );

        // Use createProfileDirect since we're already in a retry loop
        await _profileService.createProfileDirect(profileModel);

        // Read back the document to get the server-set timestamp
        final doc = await _firestoreService.getDocument(
          '${FirestoreCollections.users}/$uid',
        );

        if (doc == null) {
          return const Left(
              DatabaseFailure(message: 'Failed to create user profile'));
        }

        // Record device session for registration
        _recordDeviceSession(uid, 'register');

        return Right(UserModel.fromFirestore(doc).toEntity());
      } on ArgumentError catch (e) {
        // Don't retry argument errors - they won't be fixed by retrying
        return Left(DatabaseFailure(
          message: 'Invalid user profile data: ${e.message}',
          code: 'invalid-data',
        ));
      } catch (e) {
        lastError = e;
        
        // Check if it's a permission-denied error (auth token not propagated yet)
        final errorString = e.toString().toLowerCase();
        final isPermissionError = errorString.contains('permission-denied') || 
                                  errorString.contains('permission_denied') ||
                                  errorString.contains('permission denied');
        final isLastAttempt = attempt == maxRetries - 1;
        
        if (isPermissionError && !isLastAttempt) {
          // Wait with exponential backoff before retrying
          final delay = baseDelay * (attempt + 1);
          await Future.delayed(delay);
          
          // Force refresh the token again before retry
          await _authService.getIdToken(forceRefresh: true);
          continue;
        }
        
        // For non-permission errors or if all retries exhausted, break out
        break;
      }
    }
    
    // All retries failed - return appropriate error
    if (lastError is DatabaseException) {
      return Left(DatabaseFailure(
        message: lastError.message,
        code: lastError.code,
      ));
    }
    
    return Left(UnexpectedFailure(
      message: lastError?.toString() ?? 'Profile creation failed after retries',
    ));
  }

  /// Record device session for security and debugging purposes.
  /// This runs in the background and does not block authentication flow.
  void _recordDeviceSession(String userId, String sessionType) {
    // Run asynchronously without blocking
    Future(() async {
      try {
        final session = await _deviceInfoService.collectDeviceSession(
          userId,
          sessionType,
        );
        await _deviceSessionRepository.saveDeviceSession(session);
      } catch (_) {
        // Silently swallow â€“ crash reporting should handle this in production
      }
    });
  }

  /// Users whose profile migration has already been attempted this session.
  /// Avoids redundant Firestore reads on every auth stream event.
  final Set<String> _profileMigrationAttempted = {};

  /// Ensures that a profile document exists in the profiles collection.
  /// This is a migration helper for existing users created before profiles collection sync.
  /// Runs asynchronously without blocking the authentication flow.
  void _ensureProfileExists(String userId, Map<String, dynamic> userDoc) {
    // Skip if already attempted for this user this session.
    if (_profileMigrationAttempted.contains(userId)) return;
    _profileMigrationAttempted.add(userId);

    Future(() async {
      try {
        // Check if profile already exists in profiles collection
        final profileDoc = await _firestoreService.getDocument(
          '${FirestoreCollections.profiles}/$userId',
        );

        if (profileDoc != null) {
          // Profile already exists, no need to create
          return;
        }

        // Profile doesn't exist, create it from users collection data
        final displayName = userDoc['displayName'] as String?;
        final photoUrl = userDoc['photoUrl'] as String?;
        final bio = userDoc['bio'] as String?;
        final vibe = userDoc['vibe'] as String?;
        final mood = userDoc['mood'] as String?;
        final gender = userDoc['gender'] as String?;
        final isVisible = userDoc['isVisible'] as bool? ?? true;
        final createdAt = (userDoc['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        // Create full profile model
        final profileModel = ProfileModel(
          id: userId,
          userId: userId,
          name: displayName ?? '',
          bio: bio ?? '',
          photoUrl: photoUrl,
          isVisible: isVisible,
          showOnlineStatus: true,
          allowConnectionRequests: true,
          showLastSeen: true,
          vibe: vibe,
          mood: mood,
          gender: gender,
          createdAt: createdAt,
          updatedAt: DateTime.now(),
        );

        await _profileService.createProfile(profileModel);
      } catch (_) {
        // Log error but don't fail - profile will be created on next update
      }
    });
  }
}
