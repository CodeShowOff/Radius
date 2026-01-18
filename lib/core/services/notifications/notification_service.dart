import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

/// Service for managing push notifications via Firebase Cloud Messaging.
///
/// Handles:
/// - FCM token registration and updates
/// - Foreground notification display
/// - Background notification handling
/// - Notification permissions
/// - Badge counts
class NotificationService {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final Logger _logger;

  String? _currentUserId;
  String? _fcmToken;

  /// Track which conversation the user is currently viewing
  String? _currentConversationId;

  /// Callback for showing in-app notifications (e.g., SnackBar)
  void Function(String title, String body, Map<String, dynamic> data)?
      onInAppNotification;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotifications,
    Logger? logger,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _logger = logger ?? Logger();

  /// Initialize notification service for the given user.
  Future<void> initialize(String userId) async {
    _currentUserId = userId;

    try {
      // Request permissions (iOS/Web)
      await _requestPermissions();

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get and save FCM token
      await _setupFCMToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_onTokenRefresh);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      _logger.i('Notification service initialized for user: $userId');
    } catch (e, stack) {
      _logger.e('Error initializing notifications',
          error: e, stackTrace: stack);
    }
  }

  /// Request notification permissions (iOS/Web).
  Future<bool> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    _logger.i('Notification permission: ${settings.authorizationStatus}');
    return authorized;
  }

  /// Initialize local notifications plugin for foreground display.
  Future<void> _initializeLocalNotifications() async {
    // Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'radius_messages', // id
      'Messages', // name
      description: 'Notifications for new messages and connection requests',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Create Android channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    // Initialize settings
    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Setup FCM token and save to Firestore.
  Future<void> _setupFCMToken() async {
    if (_currentUserId == null) return;

    try {
      // Get FCM token
      final token = await _messaging.getToken();
      if (token == null) {
        _logger.w('FCM token is null');
        return;
      }

      _fcmToken = token;
      _logger.i('FCM Token: $token');

      // Save token to Firestore
      await _saveTokenToFirestore(token);
    } catch (e, stack) {
      _logger.e('Error setting up FCM token', error: e, stackTrace: stack);
    }
  }

  /// Save FCM token to Firestore.
  Future<void> _saveTokenToFirestore(String token) async {
    if (_currentUserId == null) return;

    try {
      await _firestore.collection('users').doc(_currentUserId).set({
        'fcmTokens': {
          token: {
            'addedAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.name,
          }
        },
      }, SetOptions(merge: true));

      _logger.i('FCM token saved to Firestore');
    } catch (e, stack) {
      _logger.e('Error saving FCM token', error: e, stackTrace: stack);
    }
  }

  /// Handle token refresh.
  void _onTokenRefresh(String newToken) {
    _fcmToken = newToken;
    _logger.i('FCM Token refreshed: $newToken');
    _saveTokenToFirestore(newToken);
  }

  /// Handle foreground messages (app is open).
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.i('Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    final messageConversationId = message.data['conversationId'] as String?;
    final messageType = message.data['type'] as String?;

    // Check if user is viewing the conversation that received a message
    final isViewingConversation = messageType == 'message' &&
        messageConversationId != null &&
        messageConversationId == _currentConversationId;

    if (isViewingConversation) {
      // User is viewing this chat - don't show any notification
      _logger.d(
          'User is viewing conversation $messageConversationId - suppressing notification');
      return;
    }

    // User is not viewing this chat - show in-app notification
    if (notification != null) {
      // Show in-app notification (SnackBar) if callback is registered
      if (onInAppNotification != null && messageType == 'message') {
        onInAppNotification!(
          notification.title ?? 'New Message',
          notification.body ?? '',
          message.data,
        );
      }

      // Also show system notification banner
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'radius_messages',
            'Messages',
            channelDescription:
                'Notifications for new messages and connection requests',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/launcher_icon',
            playSound: true,
            enableVibration: true,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data['conversationId'] ?? message.data['requestId'],
      );
    }
  }

  /// Handle notification tap.
  void _onNotificationTapped(NotificationResponse response) {
    _logger.i('Notification tapped: ${response.payload}');

    // Navigation will be handled by the app router
    // The payload contains conversationId or requestId
  }

  /// Update app badge count (unread messages + pending requests).
  Future<void> updateBadgeCount(int count) async {
    try {
      // iOS badge
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(badge: true);

      // Android badge (handled by notification channels)
      _logger.d('Badge count updated: $count');
    } catch (e) {
      _logger.e('Error updating badge count', error: e);
    }
  }

  /// Clear all notifications.
  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  /// Set the current conversation the user is viewing.
  /// This prevents showing notifications for messages in this conversation.
  void setCurrentConversation(String? conversationId) {
    _currentConversationId = conversationId;
    _logger.d('Current conversation set to: $conversationId');
  }

  /// Clear the current conversation (user left the chat screen).
  void clearCurrentConversation() {
    _currentConversationId = null;
    _logger.d('Current conversation cleared');
  }

  /// Remove FCM token on sign out.
  Future<void> removeToken() async {
    if (_currentUserId == null || _fcmToken == null) return;

    try {
      await _firestore.collection('users').doc(_currentUserId).update({
        'fcmTokens.$_fcmToken': FieldValue.delete(),
      });

      await _messaging.deleteToken();
      _fcmToken = null;
      _currentUserId = null;

      _logger.i('FCM token removed');
    } catch (e, stack) {
      _logger.e('Error removing FCM token', error: e, stackTrace: stack);
    }
  }
}

/// Background message handler (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  // await Firebase.initializeApp();

  Logger().i('Background message: ${message.notification?.title}');
}
