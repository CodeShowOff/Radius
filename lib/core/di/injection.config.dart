// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

import 'package:get_it/get_it.dart' as _i1;
import 'package:injectable/injectable.dart' as _i2;

import '../../features/auth/data/repositories/auth_repository_impl.dart' as _i6;
import '../../features/auth/domain/repositories/i_auth_repository.dart' as _i5;
import '../../features/auth/presentation/bloc/auth_bloc.dart' as _i7;
import '../../features/chat/data/chat_service.dart' as _i19;
import '../../features/chat/presentation/bloc/chat_bloc.dart' as _i20;
import '../../features/chat/presentation/bloc/conversations_bloc.dart' as _i21;
import '../../features/connections/data/connection_service.dart' as _i17;
import '../../features/connections/presentation/bloc/connection_bloc.dart'
    as _i18;
import '../../features/profile/data/repositories/profile_repository_impl.dart'
    as _i10;
import '../../features/profile/domain/repositories/i_profile_repository.dart'
    as _i9;
import '../../features/profile/presentation/bloc/profile_bloc.dart' as _i11;
import '../../features/proximity/presentation/bloc/nearby_users_bloc.dart'
    as _i14;
import '../../features/proximity/proximity_service.dart' as _i13;
import '../services/analytics/analytics_service.dart' as _i22;
import '../services/bluetooth/bluetooth_service.dart' as _i12;
import '../services/crash/crash_service.dart' as _i23;
import '../services/firebase/firebase_auth_service.dart' as _i3;
import '../services/firebase/firestore_batcher.dart' as _i24;
import '../services/firebase/firestore_cache.dart' as _i25;
import '../services/firebase/firestore_service.dart' as _i4;
import '../services/firebase/profile_service.dart' as _i8;
import '../services/firebase/username_service.dart' as _i15;

extension GetItInjectableX on _i1.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  _i1.GetIt init({
    String? environment,
    _i2.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i2.GetItHelper(
      this,
      environment,
      environmentFilter,
    );

    // ==================== SERVICES ====================

    // Analytics Service
    gh.lazySingleton<_i22.AnalyticsService>(
      () => _i22.AnalyticsService(),
    );

    // Crash Service
    gh.lazySingleton<_i23.CrashService>(
      () => _i23.CrashService(),
    );

    // Firestore Batcher
    gh.lazySingleton<_i24.FirestoreBatcher>(
      () => _i24.FirestoreBatcher(),
    );

    // Firestore Cache
    gh.lazySingleton<_i25.FirestoreCache>(
      () => _i25.FirestoreCache(),
    );

    // Firebase Auth Service
    gh.lazySingleton<_i3.FirebaseAuthService>(
      () => _i3.FirebaseAuthService(),
    );

    // Firestore Service
    gh.lazySingleton<_i4.FirestoreService>(
      () => _i4.FirestoreService(),
    );

    // Profile Service
    gh.lazySingleton<_i8.ProfileService>(
      () => _i8.ProfileService(),
    );

    // Username Service
    gh.lazySingleton<_i15.UsernameService>(
      () => _i15.UsernameService(),
    );

    // Bluetooth Service (singleton for app lifecycle)
    gh.lazySingleton<_i12.BluetoothService>(
      () => _i12.BluetoothService(),
    );

    // Proximity Service (depends on Bluetooth and UsernameService)
    gh.lazySingleton<_i13.ProximityService>(
      () => _i13.ProximityService(
        bluetoothService: gh<_i12.BluetoothService>(),
        usernameService: gh<_i15.UsernameService>(),
      ),
    );

    // ==================== REPOSITORIES ====================

    // Auth Repository
    gh.lazySingleton<_i5.IAuthRepository>(
      () => _i6.AuthRepositoryImpl(
        authService: gh<_i3.FirebaseAuthService>(),
        firestoreService: gh<_i4.FirestoreService>(),
        usernameService: gh<_i15.UsernameService>(),
      ),
    );

    // Profile Repository
    gh.lazySingleton<_i9.IProfileRepository>(
      () => _i10.ProfileRepositoryImpl(
        profileService: gh<_i8.ProfileService>(),
      ),
    );

    // ==================== BLOCS ====================

    // Auth BLoC
    gh.factory<_i7.AuthBloc>(
      () => _i7.AuthBloc(authRepository: gh<_i5.IAuthRepository>()),
    );

    // Profile BLoC
    gh.factory<_i11.ProfileBloc>(
      () => _i11.ProfileBloc(profileRepository: gh<_i9.IProfileRepository>()),
    );

    // Nearby Users BLoC
    gh.factory<_i14.NearbyUsersBloc>(
      () => _i14.NearbyUsersBloc(proximityService: gh<_i13.ProximityService>()),
    );

    // Connection Service
    gh.lazySingleton<_i17.ConnectionService>(
      () => _i17.ConnectionService(),
    );

    // Connection BLoC
    gh.factory<_i18.ConnectionBloc>(
      () =>
          _i18.ConnectionBloc(connectionService: gh<_i17.ConnectionService>()),
    );

    // ==================== CHAT ====================

    // Chat Service
    gh.lazySingleton<_i19.ChatService>(
      () => _i19.ChatService(),
    );

    // Chat BLoC (factory - one per conversation)
    gh.factory<_i20.ChatBloc>(
      () => _i20.ChatBloc(chatService: gh<_i19.ChatService>()),
    );

    // Conversations BLoC
    gh.factory<_i21.ConversationsBloc>(
      () => _i21.ConversationsBloc(chatService: gh<_i19.ChatService>()),
    );

    return this;
  }
}
