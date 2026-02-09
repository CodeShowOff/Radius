import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:radius/core/error/failures.dart';
import 'package:radius/features/auth/domain/entities/user.dart';
import 'package:radius/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:radius/features/auth/presentation/bloc/auth_bloc.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  late AuthBloc authBloc;
  late MockAuthRepository mockAuthRepository;

  setUpAll(() async {
    // Initialize Hive for tests
    Hive.init('./test/hive_test');
    
    // Mock path_provider channel for AppDataClearer
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getTemporaryDirectory') {
          return '/tmp';
        }
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return '/tmp/docs';
        }
        return null;
      },
    );
  });

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    // Mock authStateChanges stream to prevent subscription errors
    when(() => mockAuthRepository.authStateChanges)
        .thenAnswer((_) => const Stream.empty()); // Empty stream prevents immediate state change
    authBloc = AuthBloc(authRepository: mockAuthRepository);
  });

  tearDown(() {
    authBloc.close();
  });

  group('AuthBloc', () {
    final testUser = User(
      id: 'test-id',
      email: 'test@example.com',
      displayName: 'Test User',
      username: 'testuser',
      createdAt: DateTime.now(),
    );

    test('initial state is AuthInitial', () {
      expect(authBloc.state, isA<AuthInitial>());
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when AuthCheckRequested succeeds with verified user',
      build: () {
        when(() => mockAuthRepository.getCurrentUser())
            .thenAnswer((_) async => Right(testUser));
        when(() => mockAuthRepository.isEmailVerified).thenReturn(true);
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when AuthCheckRequested returns null',
      build: () {
        when(() => mockAuthRepository.getCurrentUser())
            .thenAnswer((_) async => const Right(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAwaitingEmailVerification] when user email not verified',
      build: () {
        when(() => mockAuthRepository.getCurrentUser())
            .thenAnswer((_) async => Right(testUser));
        when(() => mockAuthRepository.isEmailVerified).thenReturn(false);
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAwaitingEmailVerification>()
            .having((s) => s.email, 'email', testUser.email)
            .having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when AuthCheckRequested fails',
      build: () {
        when(() => mockAuthRepository.getCurrentUser())
            .thenAnswer((_) async => const Left(ServerFailure(message: 'Connection error')));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthCheckRequested()),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when sign out succeeds',
      build: () {
        when(() => mockAuthRepository.signOut())
            .thenAnswer((_) async => const Right(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthSignOutRequested()),
      wait: const Duration(seconds: 2),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthUnauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when sign out fails',
      build: () {
        when(() => mockAuthRepository.signOut())
            .thenAnswer((_) async => const Left(ServerFailure(message: 'Sign out failed')));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthSignOutRequested()),
      wait: const Duration(seconds: 2),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having((s) => s.message, 'message', 'Sign out failed'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when sign in succeeds with verified email',
      build: () {
        when(() => mockAuthRepository.signInWithEmail(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenAnswer((_) async => Right(testUser));
        when(() => mockAuthRepository.isEmailVerified).thenReturn(true);
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthSignInRequested(
        email: 'test@example.com',
        password: 'password123',
      )),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthAuthenticated>().having((s) => s.user, 'user', testUser),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when sign in fails',
      build: () {
        when(() => mockAuthRepository.signInWithEmail(
              email: any(named: 'email'),
              password: any(named: 'password'),
            )).thenAnswer((_) async => const Left(AuthFailure(message: 'Invalid credentials')));
        return authBloc;
      },
      act: (bloc) => bloc.add(const AuthSignInRequested(
        email: 'test@example.com',
        password: 'wrongpassword',
      )),
      expect: () => [
        isA<AuthLoading>(),
        isA<AuthError>().having((s) => s.message, 'message', 'Invalid credentials'),
      ],
    );
  });
}
