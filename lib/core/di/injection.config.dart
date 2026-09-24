// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:cloud_firestore/cloud_firestore.dart' as _i974;
import 'package:firebase_auth/firebase_auth.dart' as _i59;
import 'package:firebase_messaging/firebase_messaging.dart' as _i892;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as _i163;
import 'package:get_it/get_it.dart' as _i174;
import 'package:google_sign_in/google_sign_in.dart' as _i116;
import 'package:injectable/injectable.dart' as _i526;
import 'package:logger/logger.dart' as _i974;
import 'package:stream_chat_flutter/stream_chat_flutter.dart' as _i981;

import '../../features/auth/data/repositories/auth_repository_impl.dart'
    as _i153;
import '../../features/auth/domain/repositories/i_auth_repository.dart'
    as _i589;
import '../device_session/data/repositories/device_session_repository.dart'
    as _i51;
import '../device_session/data/services/device_info_service.dart' as _i819;
import '../device_session/domain/repositories/i_device_session_repository.dart'
    as _i199;
import '../services/firebase/firebase_auth_service.dart' as _i491;
import '../services/firebase/firestore_service.dart' as _i939;
import '../services/firebase/profile_service.dart' as _i759;
import '../services/firebase/username_service.dart' as _i615;
import '../services/notifications/notification_navigation_service.dart'
    as _i132;
import '../services/notifications/notification_service.dart' as _i485;
import '../services/stream_token_service.dart' as _i187;
import 'firebase_module.dart' as _i616;
import 'notification_module.dart' as _i288;
import 'stream_chat_module.dart' as _i715;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final firebaseModule = _$FirebaseModule();
    final notificationModule = _$NotificationModule();
    final streamChatModule = _$StreamChatModule();
    gh.lazySingleton<_i819.DeviceInfoService>(() => _i819.DeviceInfoService());
    gh.lazySingleton<_i974.FirebaseFirestore>(() => firebaseModule.firestore);
    gh.lazySingleton<_i59.FirebaseAuth>(() => firebaseModule.firebaseAuth);
    gh.lazySingleton<_i116.GoogleSignIn>(() => firebaseModule.googleSignIn);
    gh.lazySingleton<_i974.Logger>(() => firebaseModule.logger);
    gh.lazySingleton<_i892.FirebaseMessaging>(
        () => notificationModule.firebaseMessaging);
    gh.lazySingleton<_i163.FlutterLocalNotificationsPlugin>(
        () => notificationModule.localNotifications);
    gh.lazySingleton<_i981.StreamChatClient>(
        () => streamChatModule.streamChatClient);
    gh.lazySingleton<_i187.StreamTokenService>(
        () => _i187.StreamTokenService(logger: gh<_i974.Logger>()));
    gh.lazySingleton<_i491.FirebaseAuthService>(() => _i491.FirebaseAuthService(
          firebaseAuth: gh<_i59.FirebaseAuth>(),
          googleSignIn: gh<_i116.GoogleSignIn>(),
        ));
    gh.lazySingleton<_i132.NotificationNavigationService>(() =>
        notificationModule
            .notificationNavigationService(gh<_i892.FirebaseMessaging>()));
    gh.lazySingleton<_i939.FirestoreService>(
        () => _i939.FirestoreService(firestore: gh<_i974.FirebaseFirestore>()));
    gh.lazySingleton<_i759.ProfileService>(
        () => _i759.ProfileService(firestore: gh<_i974.FirebaseFirestore>()));
    gh.lazySingleton<_i615.UsernameService>(
        () => _i615.UsernameService(firestore: gh<_i974.FirebaseFirestore>()));
    gh.lazySingleton<_i485.NotificationService>(
        () => notificationModule.notificationService(
              gh<_i892.FirebaseMessaging>(),
              gh<_i163.FlutterLocalNotificationsPlugin>(),
              gh<_i132.NotificationNavigationService>(),
            ));
    gh.lazySingleton<_i199.IDeviceSessionRepository>(() =>
        _i51.DeviceSessionRepository(firestore: gh<_i974.FirebaseFirestore>()));
    gh.lazySingleton<_i589.IAuthRepository>(() => _i153.AuthRepositoryImpl(
          authService: gh<_i491.FirebaseAuthService>(),
          firestoreService: gh<_i939.FirestoreService>(),
          profileService: gh<_i759.ProfileService>(),
          deviceInfoService: gh<_i819.DeviceInfoService>(),
          deviceSessionRepository: gh<_i199.IDeviceSessionRepository>(),
          usernameService: gh<_i615.UsernameService>(),
        ));
    return this;
  }
}

class _$FirebaseModule extends _i616.FirebaseModule {}

class _$NotificationModule extends _i288.NotificationModule {}

class _$StreamChatModule extends _i715.StreamChatModule {}
