import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

import 'notification_navigation_service.dart';

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
  final NotificationNavigationService? _navigationService;

  String? _currentUserId;
  String? _fcmToken;

  /// Track which conversation the user is currently viewing
  String? _currentConversationId;

  /// Track which group chat the user is currently viewing
  String? _currentGroupId;

  /// Callback for showing in-app notifications (e.g., SnackBar)
  void Function(String title, String body, Map<String, dynamic> data)?
      onInAppNotification;

  NotificationService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    FlutterLocalNotificationsPlugin? localNotifications,
    NotificationNavigationService? navigationService,
    Logger? logger,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _navigationService = navigationService,
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

      // Initialize navigation service for deep linking
      await _navigationService?.initialize();

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
    // Android notification channel for messages
    // Using Importance.max for heads-up notifications (banner at top of screen)
    const androidMessagesChannel = AndroidNotificationChannel(
      'radius_messages', // id
      'Messages', // name
      description: 'Notifications for new messages and connection requests',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Android notification channel for nearby help - CRITICAL FIX: This channel was missing!
    // Without this channel, Android may not display nearby help notifications properly.
    // Using Importance.max for heads-up notifications (banner at top of screen)
    const androidNearbyHelpChannel = AndroidNotificationChannel(
      'radius_nearby_help', // id - matches Firebase Functions channel ID
      'Nearby Help', // name
      description: 'Notifications for nearby help requests',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Create Android channels
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    await androidPlugin?.createNotificationChannel(androidMessagesChannel);
    await androidPlugin?.createNotificationChannel(androidNearbyHelpChannel);

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
    final messageGroupId = message.data['groupId'] as String?;
    final messageType = message.data['type'] as String?;
    final requestId = message.data['requestId'] as String?;

    // Check if user is viewing the conversation that received a message
    final isViewingConversation = messageType == 'message' &&
        messageConversationId != null &&
        messageConversationId == _currentConversationId;

    // Check if user is viewing the group chat that received a message
    final isViewingGroupChat = messageType == 'group_message' &&
        messageGroupId != null &&
        messageGroupId == _currentGroupId;

    if (isViewingConversation) {
      // User is viewing this chat - don't show any notification
      _logger.d(
          'User is viewing conversation $messageConversationId - suppressing notification');
      return;
    }

    if (isViewingGroupChat) {
      // User is viewing this group chat - don't show any notification
      _logger.d(
          'User is viewing group $messageGroupId - suppressing notification');
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

      // Determine the correct notification channel based on message type
      // CRITICAL FIX: Use the correct channel for nearby help notifications
      final isNearbyHelp = messageType?.startsWith('nearby_help') ?? false;
      final channelId = isNearbyHelp ? 'radius_nearby_help' : 'radius_messages';
      final channelName = isNearbyHelp ? 'Nearby Help' : 'Messages';
      final channelDescription = isNearbyHelp 
          ? 'Notifications for nearby help requests'
          : 'Notifications for new messages and connection requests';

      // Also show system notification banner
      // Using Importance.max and Priority.max for heads-up notifications
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/launcher_icon',
            playSound: true,
            enableVibration: true,
            showWhen: true,
            // Additional settings for heads-up notification
            fullScreenIntent: false,
            category: AndroidNotificationCategory.message,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            // iOS will show as banner notification by default with these settings
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        // Include type in payload for proper navigation on tap
        payload: _encodePayload(
          type: messageType,
          conversationId: messageConversationId,
          groupId: messageGroupId,
          requestId: requestId,
        ),
      );
    }
  }

  /// Encode notification payload for tap handling.
  String _encodePayload({
    String? type,
    String? conversationId,
    String? groupId,
    String? requestId,
  }) {
    // Format: type|id
    if (type == 'group_message' && groupId != null) {
      return 'group_message|$groupId';
    } else if (type == 'nearby_group_message' && groupId != null) {
      return 'nearby_group_message|$groupId';
    } else if (type == 'random_group_message' && groupId != null) {
      return 'random_group_message|$groupId';
    } else if (type == 'message' && conversationId != null) {
      return 'message|$conversationId';
    } else if (type == 'connection_request' && requestId != null) {
      return 'connection_request|$requestId';
    } else if (type == 'nearby_help_request' && requestId != null) {
      return 'nearby_help_request|$requestId';
    } else if (type == 'nearby_help_assigned' && requestId != null) {
      return 'nearby_help_assigned|$requestId';
    } else if (type == 'nearby_help_completed' && requestId != null) {
      return 'nearby_help_completed|$requestId';
    } else if (type == 'nearby_help_cancelled' && requestId != null) {
      return 'nearby_help_cancelled|$requestId';
    } else if (type == 'nearby_help_expired' && requestId != null) {
      return 'nearby_help_expired|$requestId';
    }
    return conversationId ?? requestId ?? '';
  }

  /// Handle notification tap.
  void _onNotificationTapped(NotificationResponse response) {
    _logger.i('Notification tapped: ${response.payload}');

    // Use navigation service to handle the navigation
    _navigationService?.handleLocalNotificationPayload(response.payload);
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

  /// Set the current group the user is viewing.
  /// This prevents showing notifications for messages in this group.
  void setCurrentGroup(String? groupId) {
    _currentGroupId = groupId;
    _logger.d('Current group set to: $groupId');
  }

  /// Clear the current group (user left the group chat screen).
  void clearCurrentGroup() {
    _currentGroupId = null;
    _logger.d('Current group cleared');
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
