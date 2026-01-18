// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:cloud_firestore/cloud_firestore.dart' as _i974;
import 'package:firebase_auth/firebase_auth.dart' as _i59;
import 'package:firebase_messaging/firebase_messaging.dart' as _i892;
import 'package:firebase_storage/firebase_storage.dart' as _i457;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as _i163;
import 'package:get_it/get_it.dart' as _i174;
import 'package:google_sign_in/google_sign_in.dart' as _i116;
import 'package:injectable/injectable.dart' as _i526;
import 'package:logger/logger.dart' as _i974;

import '../../features/auth/data/repositories/auth_repository_impl.dart'
    as _i153;
import '../../features/auth/domain/repositories/i_auth_repository.dart'
    as _i589;
import '../../features/chat/data/chat_service.dart' as _i621;
import '../../features/chat/data/media_upload_service.dart' as _i356;
import '../../features/chat/presentation/bloc/chat_bloc.dart' as _i65;
import '../../features/chat/presentation/bloc/conversations_bloc.dart' as _i346;
import '../services/firebase/firebase_auth_service.dart' as _i491;
import '../services/firebase/firestore_service.dart' as _i939;
import '../services/firebase/profile_service.dart' as _i759;
import '../services/firebase/username_service.dart' as _i615;
import '../services/notifications/notification_service.dart' as _i485;
import 'chat_module.dart' as _i396;
import 'firebase_module.dart' as _i616;
import 'notification_module.dart' as _i288;

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
    final chatModule = _$ChatModule();
    gh.lazySingleton<_i974.FirebaseFirestore>(() => firebaseModule.firestore);
    gh.lazySingleton<_i59.FirebaseAuth>(() => firebaseModule.firebaseAuth);
    gh.lazySingleton<_i457.FirebaseStorage>(
        () => firebaseModule.firebaseStorage);
    gh.lazySingleton<_i116.GoogleSignIn>(() => firebaseModule.googleSignIn);
    gh.lazySingleton<_i974.Logger>(() => firebaseModule.logger);
    gh.lazySingleton<_i892.FirebaseMessaging>(
        () => notificationModule.firebaseMessaging);
    gh.lazySingleton<_i163.FlutterLocalNotificationsPlugin>(
        () => notificationModule.localNotifications);
    gh.lazySingleton<_i356.MediaUploadService>(
        () => chatModule.mediaUploadService(
              gh<_i457.FirebaseStorage>(),
              gh<_i974.Logger>(),
            ));
    gh.lazySingleton<_i939.FirestoreService>(
        () => _i939.FirestoreService(firestore: gh<_i974.FirebaseFirestore>()));
    gh.lazySingleton<_i621.ChatService>(() => chatModule.chatService(
          gh<_i974.FirebaseFirestore>(),
          gh<_i974.Logger>(),
        ));
    gh.factory<_i346.ConversationsBloc>(
        () => chatModule.conversationsBloc(gh<_i621.ChatService>()));
    gh.lazySingleton<_i485.NotificationService>(
        () => notificationModule.notificationService(
              gh<_i892.FirebaseMessaging>(),
              gh<_i163.FlutterLocalNotificationsPlugin>(),
            ));
    gh.lazySingleton<_i491.FirebaseAuthService>(() => _i491.FirebaseAuthService(
          firebaseAuth: gh<_i59.FirebaseAuth>(),
          googleSignIn: gh<_i116.GoogleSignIn>(),
        ));
    gh.factory<_i65.ChatBloc>(() => chatModule.chatBloc(
          gh<_i621.ChatService>(),
          gh<_i356.MediaUploadService>(),
        ));
    gh.lazySingleton<_i589.IAuthRepository>(() => _i153.AuthRepositoryImpl(
          authService: gh<_i491.FirebaseAuthService>(),
          firestoreService: gh<_i939.FirestoreService>(),
          profileService: gh<_i759.ProfileService>(),
          usernameService: gh<_i615.UsernameService>(),
        ));
    return this;
  }
}

class _$FirebaseModule extends _i616.FirebaseModule {}

class _$NotificationModule extends _i288.NotificationModule {}

class _$ChatModule extends _i396.ChatModule {}
