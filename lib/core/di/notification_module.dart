import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';

import '../services/notifications/notification_navigation_service.dart';
import '../services/notifications/notification_service.dart';

/// Module for providing notification dependencies.
@module
abstract class NotificationModule {
  @lazySingleton
  FirebaseMessaging get firebaseMessaging => FirebaseMessaging.instance;

  @lazySingleton
  FlutterLocalNotificationsPlugin get localNotifications =>
      FlutterLocalNotificationsPlugin();

  @lazySingleton
  NotificationNavigationService notificationNavigationService(
    FirebaseMessaging messaging,
  ) =>
      NotificationNavigationService(
        messaging: messaging,
      );

  @lazySingleton
  NotificationService notificationService(
    FirebaseMessaging messaging,
    FlutterLocalNotificationsPlugin localNotifications,
    NotificationNavigationService navigationService,
  ) =>
      NotificationService(
        messaging: messaging,
        localNotifications: localNotifications,
        navigationService: navigationService,
      );
}
