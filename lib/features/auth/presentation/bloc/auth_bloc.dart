import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/services/app_data_clearer.dart';
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

  /// Whether the initial auth check (AuthCheckRequested) has completed.
  /// The authStateChanges subscription is deferred until after this to avoid
  /// a redundant Firestore query and state churn on startup.
  bool _initialCheckDone = false;

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
    on<AuthResendVerificationRequested>(_onResendVerificationRequested);
    on<AuthCheckEmailVerificationRequested>(_onCheckEmailVerificationRequested);

    // NOTE: authStateChanges subscription is NOT started here.
    // It is deferred until after the first AuthCheckRequested completes
    // (see _startAuthStateSubscription). This eliminates a redundant
    // Firestore query and prevents the race condition where the stream's
    // asyncMap fires concurrently with getCurrentUser(), causing a
    // AuthLoading flash and double navigation.
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    // NOTE: AuthLoading is intentionally NOT emitted here.
    // getCurrentUser() uses Firestore's local cache first (~0 ms for
    // returning users), so the result is available almost instantly.
    // Emitting AuthLoading would force GoRouter to trap the user on
    // the splash screen for an extra frame, adding perceived delay.
    // For cache-miss (first install) the state stays AuthInitial which
    // the router already handles identically to AuthLoading.

    final result = await _authRepository.getCurrentUser();
    result.fold(
      (failure) => emit(AuthUnauthenticated()),
      (user) {
        if (user == null) {
          emit(AuthUnauthenticated());
        } else if (!_authRepository.isEmailVerified) {
          // User exists but email not verified
          emit(AuthAwaitingEmailVerification(email: user.email, user: user));
        } else {
          emit(AuthAuthenticated(user));
        }
      },
    );

    // Start listening for external auth changes (token expiry, account
    // deletion, etc.) now that the initial check is done. On subscription,
    // Firebase emits the current user — the asyncMap Firestore query still
    // runs, but _onAuthStateChanged will early-return because the state
    // already matches, so no visible state churn occurs.
    _startAuthStateSubscription();
  }

  /// Begin listening to the repository's authStateChanges stream.
  /// Called once after the initial auth check to avoid duplicate Firestore
  /// queries and race conditions on startup.
  void _startAuthStateSubscription() {
    if (_initialCheckDone) return; // Already subscribed
    _initialCheckDone = true;
    _authStateSubscription ??= _authRepository.authStateChanges.listen(
      (user) => add(AuthStateChanged(user)),
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

      Failure? signInFailure;
      User? signedInUser;
      result.fold(
        (failure) => signInFailure = failure,
        (user) => signedInUser = user,
      );

      if (emit.isDone) return;

      if (signInFailure != null) {
        emit(AuthError(signInFailure!.message));
        return;
      }

      final user = signedInUser!;

      // Check if email is verified before allowing sign in
      if (!_authRepository.isEmailVerified) {
        // Send verification email if not already sent recently
        try {
          await _authRepository.sendEmailVerification();
        } catch (_) {
          // Ignore errors (email might have been sent recently)
          // User can still use the resend button
        }

        if (emit.isDone) return;
        emit(AuthAwaitingEmailVerification(email: user.email, user: user));
      } else {
        emit(AuthAuthenticated(user));
      }
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
        (user) => emit(AuthAwaitingEmailVerification(
          email: event.email,
          user: user,
        )),
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
      // Clear ALL local app data (equivalent to Android's "Clear Data").
      // This wipes Hive boxes, in-memory caches, image cache, temp files,
      // and notifications so the next session starts completely fresh.
      try {
        await AppDataClearer.clearAllAppData();
      } catch (_) {
        // Data clearing is best-effort; don't block sign-out if it fails.
      }

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

  Future<void> _onResendVerificationRequested(
    AuthResendVerificationRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;
    if (currentState is! AuthAwaitingEmailVerification) return;

    final result = await _authRepository.sendEmailVerification();

    Failure? failureToShow;
    result.fold(
      (failure) => failureToShow = failure,
      (_) {},
    );

    if (emit.isDone) return;

    if (failureToShow != null) {
      // Emit error for UI feedback, then immediately return to awaiting state.
      // Keeping the awaiting state ensures the periodic verification check keeps running.
      emit(AuthError(failureToShow!.message));
      emit(AuthAwaitingEmailVerification(
        email: currentState.email,
        user: currentState.user,
      ));
      return;
    }

    // Emit a one-shot success state for UI feedback, then return to awaiting state.
    emit(AuthVerificationEmailSent(currentState.email, currentState.user));
    emit(AuthAwaitingEmailVerification(
      email: currentState.email,
      user: currentState.user,
    ));
  }

  Future<void> _onCheckEmailVerificationRequested(
    AuthCheckEmailVerificationRequested event,
    Emitter<AuthState> emit,
  ) async {
    final currentState = state;

    final User verificationUser;
    if (currentState is AuthAwaitingEmailVerification) {
      verificationUser = currentState.user;
    } else if (currentState is AuthVerificationEmailSent) {
      verificationUser = currentState.user;
    } else {
      return;
    }

    final result = await _authRepository.checkEmailVerified();

    Failure? verificationFailure;
    bool? isVerified;
    result.fold(
      (failure) => verificationFailure = failure,
      (value) => isVerified = value,
    );

    if (verificationFailure != null) {
      // Silently ignore errors during background checks
      // Only log in debug mode
      assert(() {
        // ignore: avoid_print
        print('Email verification check error: ${verificationFailure!.message}');
        return true;
      }());
      return;
    }

    if (isVerified != true) {
      return;
    }

    if (emit.isDone) return;

    // Email is verified! Fetch the updated user from Firestore
    final userResult = await _authRepository.getCurrentUser();

    if (emit.isDone) return;

    User? firestoreUser;
    userResult.fold(
      (_) {},
      (user) => firestoreUser = user,
    );

    emit(AuthAuthenticated(firestoreUser ?? verificationUser));
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

    // Don't interrupt awaiting email verification state from external changes
    if (currentState is AuthAwaitingEmailVerification) {
      return;
    }

    if (event.user != null) {
      if (currentState is AuthAuthenticated &&
          currentState.user.id == event.user!.id) {
        return; // Already authenticated with the same user
      }
      // Check email verification for external auth state changes
      if (!_authRepository.isEmailVerified) {
        emit(AuthAwaitingEmailVerification(
          email: event.user!.email,
          user: event.user!,
        ));
      } else {
        emit(AuthAuthenticated(event.user!));
      }
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
