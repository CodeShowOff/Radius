import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

import '../services/bluetooth/bluetooth_service.dart';
import '../services/firebase/profile_service.dart';
import '../services/firebase/username_service.dart';
import '../services/realtime/realtime_connection_service.dart';
import '../services/realtime/realtime_data_manager.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/chat/presentation/bloc/conversations_bloc.dart';
import '../../features/connections/data/connection_service.dart';
import '../../features/connections/presentation/bloc/connection_bloc.dart';
import '../../features/location_groups/data/group_chat_service.dart';
import '../../features/location_groups/data/location_data_service.dart';
import '../../features/location_groups/data/location_group_service.dart';
import '../../features/location_groups/presentation/bloc/group_chat_bloc.dart';
import '../../features/location_groups/presentation/bloc/location_group_bloc.dart';
import '../../features/profile/data/repositories/profile_repository_impl.dart';
import '../../features/profile/domain/repositories/i_profile_repository.dart';
import '../../features/profile/presentation/bloc/profile_bloc.dart';
import '../../features/proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../features/proximity/proximity_service.dart';
import '../../features/guess_me/data/guess_me_service.dart';
import '../../features/guess_me/presentation/bloc/guess_me_bloc.dart';
import '../settings/app_settings_store.dart';
import '../theme/theme_cubit.dart';

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

  // Real-time connection monitoring service
  if (!getIt.isRegistered<RealtimeConnectionService>()) {
    getIt.registerLazySingleton<RealtimeConnectionService>(
      () => RealtimeConnectionService(),
    );
  }

  if (!getIt.isRegistered<IProfileRepository>()) {
    getIt.registerLazySingleton<IProfileRepository>(
      () => ProfileRepositoryImpl(profileService: getIt<ProfileService>()),
    );
  }

  // App settings (Hive-backed when available)
  if (!getIt.isRegistered<AppSettingsStore>()) {
    getIt.registerLazySingleton<AppSettingsStore>(
      () {
        Box<dynamic>? box;
        if (getIt.isRegistered<Box<dynamic>>(instanceName: 'radius_settings')) {
          box = getIt<Box<dynamic>>(instanceName: 'radius_settings');
        }
        return AppSettingsStore(box: box);
      },
    );
  }

  if (!getIt.isRegistered<ThemeCubit>()) {
    getIt.registerLazySingleton<ThemeCubit>(
      () => ThemeCubit(settings: getIt<AppSettingsStore>()),
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

  // App-wide BLoCs - these must be singletons to maintain persistent real-time streams
  if (!getIt.isRegistered<AuthBloc>()) {
    getIt.registerFactory<AuthBloc>(
      () => AuthBloc(authRepository: getIt()),
    );
  }

  if (!getIt.isRegistered<ConnectionBloc>()) {
    getIt.registerLazySingleton<ConnectionBloc>(
      () => ConnectionBloc(connectionService: getIt()),
    );
  }

  if (!getIt.isRegistered<ProfileBloc>()) {
    getIt.registerLazySingleton<ProfileBloc>(
      () => ProfileBloc(profileRepository: getIt()),
    );
  }

  if (!getIt.isRegistered<NearbyUsersBloc>()) {
    getIt.registerFactory<NearbyUsersBloc>(
      () => NearbyUsersBloc(proximityService: getIt()),
    );
  }

  // Location Groups feature
  if (!getIt.isRegistered<LocationDataService>()) {
    getIt.registerLazySingleton<LocationDataService>(() => LocationDataService());
  }

  if (!getIt.isRegistered<LocationGroupService>()) {
    getIt.registerLazySingleton<LocationGroupService>(() => LocationGroupService());
  }

  if (!getIt.isRegistered<GroupChatService>()) {
    getIt.registerLazySingleton<GroupChatService>(() => GroupChatService());
  }

  if (!getIt.isRegistered<LocationGroupBloc>()) {
    getIt.registerLazySingleton<LocationGroupBloc>(
      () => LocationGroupBloc(
        groupService: getIt<LocationGroupService>(),
      ),
    );
  }

  if (!getIt.isRegistered<GroupChatBloc>()) {
    getIt.registerFactory<GroupChatBloc>(
      () => GroupChatBloc(chatService: getIt<GroupChatService>()),
    );
  }

  // Run generated registrations last so modules can override defaults if needed.
  getIt.init();

  // Register RealTimeDataManager after all BLoCs are registered
  // This needs to be registered after getIt.init() so that ConversationsBloc is available
  if (!getIt.isRegistered<RealTimeDataManager>()) {
    getIt.registerLazySingleton<RealTimeDataManager>(
      () => RealTimeDataManager(
        connectionService: getIt<RealtimeConnectionService>(),
        connectionBloc: getIt<ConnectionBloc>(),
        conversationsBloc: getIt<ConversationsBloc>(),
        locationGroupBloc: getIt<LocationGroupBloc>(),
        profileBloc: getIt<ProfileBloc>(),
      ),
    );
  }

  return Future.value();
}
