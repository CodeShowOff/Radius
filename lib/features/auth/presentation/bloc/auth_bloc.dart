import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// BLoC for managing authentication state.
///
/// Handles sign in, sign out, and registration flows.
/// Uses an operation flag to prevent auth state stream from racing
/// with in-progress manual auth operations.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final IAuthRepository _authRepository;
  StreamSubscription<User?>? _authStateSubscription;

  /// Flag to indicate an auth operation is in progress.
  /// When true, external auth state changes from the stream are ignored
  /// to prevent race conditions.
  bool _operationInProgress = false;

  AuthBloc({required IAuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignInWithGoogleRequested>(_onSignInWithGoogleRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<AuthPasswordResetRequested>(_onPasswordResetRequested);
    on<AuthStateChanged>(_onAuthStateChanged);

    // Listen to auth state changes from Firebase
    // This handles external auth changes (e.g., token expiry, account deletion)
    _authStateSubscription = _authRepository.authStateChanges.listen(
      (user) => add(AuthStateChanged(user)),
    );
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    final result = await _authRepository.getCurrentUser();
    result.fold(
      (failure) => emit(AuthUnauthenticated()),
      (user) => user != null
          ? emit(AuthAuthenticated(user))
          : emit(AuthUnauthenticated()),
    );
  }

  Future<void> _onSignInRequested(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    _operationInProgress = true;
    emit(AuthLoading());

    try {
      final result = await _authRepository.signInWithEmail(
        email: event.email,
        password: event.password,
      );

      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => emit(AuthAuthenticated(user)),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _onSignInWithGoogleRequested(
    AuthSignInWithGoogleRequested event,
    Emitter<AuthState> emit,
  ) async {
    _operationInProgress = true;
    emit(AuthLoading());

    try {
      final result = await _authRepository.signInWithGoogle();

      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => emit(AuthAuthenticated(user)),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    _operationInProgress = true;
    emit(AuthLoading());

    try {
      final result = await _authRepository.registerWithEmail(
        email: event.email,
        password: event.password,
        displayName: event.displayName,
      );

      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (user) => emit(AuthAuthenticated(user)),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    _operationInProgress = true;
    emit(AuthLoading());

    try {
      final result = await _authRepository.signOut();

      result.fold(
        (failure) => emit(AuthError(failure.message)),
        (_) => emit(AuthUnauthenticated()),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> _onPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _authRepository.sendPasswordResetEmail(event.email);

    result.fold(
      (failure) => emit(AuthPasswordResetFailed(failure.message)),
      (_) => emit(AuthPasswordResetSent(event.email)),
    );
  }

  void _onAuthStateChanged(
    AuthStateChanged event,
    Emitter<AuthState> emit,
  ) {
    // Ignore stream events during active operations to prevent races
    if (_operationInProgress) {
      return;
    }

    // Check if we're already in the correct state to prevent redundant emissions
    final currentState = state;
    if (event.user != null) {
      if (currentState is AuthAuthenticated &&
          currentState.user.id == event.user!.id) {
        return; // Already authenticated with the same user
      }
      emit(AuthAuthenticated(event.user!));
    } else {
      if (currentState is AuthUnauthenticated) {
        return; // Already unauthenticated
      }
      emit(AuthUnauthenticated());
    }
  }

  @override
  Future<void> close() {
    _authStateSubscription?.cancel();
    return super.close();
  }
}
