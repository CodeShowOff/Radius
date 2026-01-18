import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import '../services/bluetooth/bluetooth_service.dart';
import '../services/firebase/profile_service.dart';
import '../services/firebase/username_service.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/connections/data/connection_service.dart';
import '../../features/connections/presentation/bloc/connection_bloc.dart';
import '../../features/profile/data/repositories/profile_repository_impl.dart';
import '../../features/profile/domain/repositories/i_profile_repository.dart';
import '../../features/profile/presentation/bloc/profile_bloc.dart';
import '../../features/proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../features/proximity/proximity_service.dart';
import '../../features/guess_me/data/guess_me_service.dart';
import '../../features/guess_me/presentation/bloc/guess_me_bloc.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
Future<void> configureDependencies() {
  // ---------------------------------------------------------------------------
  // Manual registrations
  //
  // This project uses a mix of `injectable`-generated registrations plus
  // plain Dart classes (no @injectable annotations). Those plain classes must
  // be registered here to avoid runtime "not registered inside GetIt" errors.
  // ---------------------------------------------------------------------------

  if (!getIt.isRegistered<ProfileService>()) {
    getIt.registerLazySingleton<ProfileService>(() => ProfileService());
  }

  if (!getIt.isRegistered<UsernameService>()) {
    getIt.registerLazySingleton<UsernameService>(() => UsernameService());
  }

  if (!getIt.isRegistered<BluetoothService>()) {
    getIt.registerLazySingleton<BluetoothService>(() => BluetoothService());
  }

  if (!getIt.isRegistered<ProximityService>()) {
    getIt.registerLazySingleton<ProximityService>(
      () => ProximityService(
        bluetoothService: getIt<BluetoothService>(),
        usernameService: getIt<UsernameService>(),
      ),
    );
  }

  if (!getIt.isRegistered<ConnectionService>()) {
    getIt.registerLazySingleton<ConnectionService>(() => ConnectionService());
  }

  if (!getIt.isRegistered<IProfileRepository>()) {
    getIt.registerLazySingleton<IProfileRepository>(
      () => ProfileRepositoryImpl(profileService: getIt<ProfileService>()),
    );
  }

  // Guess Me feature
  if (!getIt.isRegistered<GuessmeService>()) {
    getIt.registerLazySingleton<GuessmeService>(() => GuessmeService());
  }

  if (!getIt.isRegistered<GuessmeBloc>()) {
    getIt.registerFactory<GuessmeBloc>(
      () => GuessmeBloc(service: getIt<GuessmeService>()),
    );
  }

  // App-wide BLoCs
  if (!getIt.isRegistered<AuthBloc>()) {
    getIt.registerFactory<AuthBloc>(
      () => AuthBloc(authRepository: getIt()),
    );
  }

  if (!getIt.isRegistered<ConnectionBloc>()) {
    getIt.registerFactory<ConnectionBloc>(
      () => ConnectionBloc(connectionService: getIt()),
    );
  }

  if (!getIt.isRegistered<ProfileBloc>()) {
    getIt.registerFactory<ProfileBloc>(
      () => ProfileBloc(profileRepository: getIt()),
    );
  }

  if (!getIt.isRegistered<NearbyUsersBloc>()) {
    getIt.registerFactory<NearbyUsersBloc>(
      () => NearbyUsersBloc(proximityService: getIt()),
    );
  }

  // Run generated registrations last so modules can override defaults if needed.
  getIt.init();

  return Future.value();
}
