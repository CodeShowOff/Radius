part of 'auth_bloc.dart';

/// Base class for all authentication events.
abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Event to check current authentication status.
class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

/// Event to request sign in with email/password.
class AuthSignInRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthSignInRequested({
    required this.email,
    required this.password,
  });

  // Note: Password intentionally excluded from props for security.
  // Including passwords in Equatable props can lead to them being logged
  // or appearing in debug output.
  @override
  List<Object?> get props => [email];
}

/// Event to request sign in with Google.
class AuthSignInWithGoogleRequested extends AuthEvent {
  const AuthSignInWithGoogleRequested();
}

/// Event to request new user registration.
class AuthRegisterRequested extends AuthEvent {
  final String email;
  final String password;
  final String? displayName;

  const AuthRegisterRequested({
    required this.email,
    required this.password,
    this.displayName,
  });

  // Note: Password intentionally excluded from props for security.
  // Including passwords in Equatable props can lead to them being logged
  // or appearing in debug output.
  @override
  List<Object?> get props => [email, displayName];
}

/// Event to request sign out.
class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Event to request password reset email.
class AuthPasswordResetRequested extends AuthEvent {
  final String email;

  const AuthPasswordResetRequested({required this.email});

  @override
  List<Object?> get props => [email];
}

/// Event when auth state changes externally.
class AuthStateChanged extends AuthEvent {
  final User? user;

  const AuthStateChanged(this.user);

  @override
  List<Object?> get props => [user];
}

/// Event to resend email verification.
class AuthResendVerificationRequested extends AuthEvent {
  const AuthResendVerificationRequested();
}

/// Event to check if email has been verified.
class AuthCheckEmailVerificationRequested extends AuthEvent {
  const AuthCheckEmailVerificationRequested();
}
