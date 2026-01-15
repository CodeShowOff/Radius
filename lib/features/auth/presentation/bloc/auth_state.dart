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
