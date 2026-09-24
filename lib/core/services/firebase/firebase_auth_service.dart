import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter/services.dart';

import '../../error/exceptions.dart';

/// Firebase Authentication service implementation.
///
/// Handles all authentication operations using Firebase Auth SDK.
/// Supports email/password and Google Sign-In methods.
@lazySingleton
class FirebaseAuthService {
  final firebase.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  bool _isInitialized = false;

  FirebaseAuthService({
    firebase.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? firebase.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  /// Stream of authentication state changes.
  ///
  /// Emits the current user when auth state changes (sign in/out).
  Stream<firebase.User?> get authStateChanges =>
      _firebaseAuth.authStateChanges();

  /// Stream of user changes (more granular than authStateChanges).
  ///
  /// Also emits when user profile is updated.
  Stream<firebase.User?> get userChanges => _firebaseAuth.userChanges();

  /// Currently signed-in user, or null if not authenticated.
  firebase.User? get currentUser => _firebaseAuth.currentUser;

  /// Whether a user is currently signed in.
  bool get isAuthenticated => currentUser != null;

  /// Sign in with email and password.
  ///
  /// Throws [AuthException] on failure.
  Future<firebase.User> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          message: 'Sign in failed: No user returned',
          code: 'null-user',
        );
      }

      return user;
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        message: 'Sign in failed: ${e.toString()}',
        code: 'unknown',
        originalError: e,
      );
    }
  }

  /// Create a new user with email and password.
  ///
  /// Throws [AuthException] on failure.
  Future<firebase.User> createUserWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;
      if (user == null) {
        throw const AuthException(
          message: 'Registration failed: No user returned',
          code: 'null-user',
        );
      }

      // Update display name if provided
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
        await user.reload();
      }

      return _firebaseAuth.currentUser ?? user;
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        message: 'Registration failed: ${e.toString()}',
        code: 'unknown',
        originalError: e,
      );
    }
  }

  /// Sign in with Google.
  ///
  /// Opens Google Sign-In flow and authenticates with Firebase.
  /// Throws [AuthException] on failure.
  Future<firebase.User> signInWithGoogle() async {
    try {
      // Initialize GoogleSignIn if not already done (required in v7.x)
      if (!_isInitialized) {
        await _googleSignIn.initialize(
          // Required for google_sign_in 7.x on Android
          // This is the web OAuth client ID from google-services.json
          serverClientId:
              '486551872927-5d3eojdo88vsetpsob0osu26lm6m1ue8.apps.googleusercontent.com',
        );
        _isInitialized = true;
      }

      // Trigger the Google Sign-In flow (v7 API)
      final GoogleSignInAccount googleUser =
          await _googleSignIn.authenticate(scopeHint: ['email']);

      // Obtain the auth details from the Google Sign-In (now synchronous in v7)
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // Create a new credential using idToken (accessToken not needed for Firebase)
      final credential = firebase.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        throw const AuthException(
          message: 'Google sign in failed: No user returned',
          code: 'null-user',
        );
      }

      return user;
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } on PlatformException catch (e) {
      // Handle specific Google Sign-In exceptions
      if (e.code == 'sign_in_canceled' ||
          e.message?.contains('canceled') == true) {
        throw const AuthException(
          message:
              'Sign in was cancelled. Please try again if you want to sign in.',
          code: 'sign-in-cancelled',
        );
      }
      throw AuthException(
        message: 'Google sign in failed: ${e.message ?? e.toString()}',
        code: e.code,
        originalError: e,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      // Check if it's a cancellation error in any other form
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('cancel') || errorString.contains('cancelled')) {
        throw const AuthException(
          message:
              'Sign in was cancelled. Please try again if you want to sign in.',
          code: 'sign-in-cancelled',
        );
      }
      throw AuthException(
        message: 'Google sign in failed: ${e.toString()}',
        code: 'unknown',
        originalError: e,
      );
    }
  }

  /// Sign out the current user.
  ///
  /// Signs out from both Firebase and Google (if signed in with Google).
  Future<void> signOut() async {
    try {
      await Future.wait([
        _firebaseAuth.signOut(),
        _googleSignIn.signOut(),
      ]);
    } catch (e) {
      throw AuthException(
        message: 'Sign out failed: ${e.toString()}',
        code: 'sign-out-failed',
        originalError: e,
      );
    }
  }

  /// Send a password reset email.
  ///
  /// Throws [AuthException] on failure.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthException(
        message: 'Password reset failed: ${e.toString()}',
        code: 'unknown',
        originalError: e,
      );
    }
  }

  /// Update the current user's display name.
  Future<void> updateDisplayName(String displayName) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        message: 'No user signed in',
        code: 'no-user',
      );
    }

    try {
      await user.updateDisplayName(displayName);
      await user.reload();
    } catch (e) {
      throw AuthException(
        message: 'Failed to update display name: ${e.toString()}',
        code: 'update-failed',
        originalError: e,
      );
    }
  }

  /// Update the current user's photo URL.
  Future<void> updatePhotoURL(String photoURL) async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        message: 'No user signed in',
        code: 'no-user',
      );
    }

    try {
      await user.updatePhotoURL(photoURL);
      await user.reload();
    } catch (e) {
      throw AuthException(
        message: 'Failed to update photo: ${e.toString()}',
        code: 'update-failed',
        originalError: e,
      );
    }
  }

  /// Delete the current user's account.
  ///
  /// This is a destructive operation and cannot be undone.
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        message: 'No user signed in',
        code: 'no-user',
      );
    }

    try {
      await user.delete();
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthException(
        message: 'Failed to delete account: ${e.toString()}',
        code: 'delete-failed',
        originalError: e,
      );
    }
  }

  /// Whether the current user's email is verified.
  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  /// Forces a refresh of the ID token.
  /// This ensures the auth token is fully propagated to Firebase services like Firestore.
  /// Call this after sign-in before making Firestore writes to avoid permission-denied errors.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  /// Send email verification to the current user.
  ///
  /// Throws [AuthException] on failure.
  Future<void> sendEmailVerification() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        message: 'No user signed in',
        code: 'no-user',
      );
    }

    // Check if email is already verified
    if (user.emailVerified) {
      throw const AuthException(
        message: 'Email is already verified',
        code: 'already-verified',
      );
    }

    try {
      await user.sendEmailVerification();
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthException(
        message: 'Failed to send verification email: ${e.toString()}',
        code: 'verification-failed',
        originalError: e,
      );
    }
  }

  /// Reload the current user to get updated data (e.g., email verification status).
  ///
  /// Throws [AuthException] on failure.
  Future<void> reloadUser() async {
    final user = currentUser;
    if (user == null) {
      throw const AuthException(
        message: 'No user signed in',
        code: 'no-user',
      );
    }

    try {
      await user.reload();
      // Force refresh the current user reference
      await _firebaseAuth.currentUser?.reload();
    } on firebase.FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthException(
        message: 'Failed to reload user: ${e.toString()}',
        code: 'reload-failed',
        originalError: e,
      );
    }
  }

  /// Maps Firebase Auth exceptions to our custom AuthException.
  AuthException _mapFirebaseAuthException(firebase.FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'user-not-found':
        message = 'No user found with this email address';
        break;
      case 'wrong-password':
        message = 'Incorrect password';
        break;
      case 'email-already-in-use':
        message = 'An account already exists with this email';
        break;
      case 'invalid-email':
        message = 'Invalid email address';
        break;
      case 'weak-password':
        message = 'Password is too weak. Use at least 6 characters';
        break;
      case 'user-disabled':
        message = 'This account has been disabled';
        break;
      case 'too-many-requests':
        message = 'Too many attempts. Please try again later';
        break;
      case 'operation-not-allowed':
        message = 'This sign-in method is not enabled';
        break;
      case 'requires-recent-login':
        message = 'Please sign in again to complete this action';
        break;
      case 'invalid-credential':
        message = 'Invalid credentials. Please try again';
        break;
      default:
        message = e.message ?? 'Authentication error occurred';
    }

    return AuthException(
      message: message,
      code: e.code,
      originalError: e,
    );
  }
}
