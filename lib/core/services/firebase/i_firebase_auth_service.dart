/// Firebase Auth service interface.
/// 
/// Abstracts Firebase Auth SDK for easier testing and potential migration.
/// Implementation will be added when Firebase is configured.
abstract class IFirebaseAuthService {
  /// Stream of auth state changes.
  Stream<AuthUser?> get authStateChanges;
  
  /// Currently signed-in user.
  AuthUser? get currentUser;
  
  /// Sign in with email and password.
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });
  
  /// Create new user with email and password.
  Future<AuthUser> createUserWithEmailAndPassword({
    required String email,
    required String password,
  });
  
  /// Sign out current user.
  Future<void> signOut();
  
  /// Send password reset email.
  Future<void> sendPasswordResetEmail(String email);
}

/// Simplified auth user from Firebase.
class AuthUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoURL;

  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoURL,
  });
}
