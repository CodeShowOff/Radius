part of 'auth_bloc.dart';

/// Base class for all authentication states.
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Initial state before auth check.
class AuthInitial extends AuthState {}

/// Loading state during authentication operations.
class AuthLoading extends AuthState {}

/// State when user is authenticated.
class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated(this.user);

  @override
  List<Object?> get props => [user];
}

/// State when user is not authenticated.
class AuthUnauthenticated extends AuthState {}

/// State when an authentication error occurs.
class AuthError extends AuthState {
  final String message;

  const AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when password reset email was sent successfully.
class AuthPasswordResetSent extends AuthState {
  final String email;

  const AuthPasswordResetSent(this.email);

  @override
  List<Object?> get props => [email];
}

/// State when password reset email failed to send.
class AuthPasswordResetFailed extends AuthState {
  final String message;

  const AuthPasswordResetFailed(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when awaiting email verification after registration.
class AuthAwaitingEmailVerification extends AuthState {
  final String email;
  final User user;

  const AuthAwaitingEmailVerification({
    required this.email,
    required this.user,
  });

  @override
  List<Object?> get props => [email, user];
}

/// State when verification email was resent successfully.
class AuthVerificationEmailSent extends AuthState {
  final String email;
  final User user;

  const AuthVerificationEmailSent(this.email, this.user);

  @override
  List<Object?> get props => [email, user];
}
