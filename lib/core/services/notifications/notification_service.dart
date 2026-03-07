import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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

  /// Track active notification IDs per conversation/group so we can cancel them.
  /// Key: conversationId or groupId, Value: set of notification IDs shown.
  final Map<String, Set<int>> _activeNotificationIds = {};

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
      // PRIORITY: Handle pending notification navigation immediately.
      // This must run first so tapping a notification opens the target screen
      // without waiting for permissions, channels, or FCM token setup.
      await _navigationService?.initialize();

      // Permissions and local notification channels are independent — run in parallel.
      await Future.wait([
        _requestPermissions(),
        _initializeLocalNotifications(),
      ]);

      // Get and save FCM token (depends on permissions being granted)
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
  /// Optimized to check current status first to avoid unnecessary permission dialogs.
  Future<bool> _requestPermissions() async {
    // Check current permission status first (fast, no dialog)
    final currentSettings = await _messaging.getNotificationSettings();

    // If already authorized, skip the request (saves time on app boot)
    if (currentSettings.authorizationStatus == AuthorizationStatus.authorized ||
        currentSettings.authorizationStatus ==
            AuthorizationStatus.provisional) {
      _logger.i(
          'Notification permission already granted: ${currentSettings.authorizationStatus}');
      return true;
    }

    // Request permissions if not yet granted
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
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
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
      settings: initializationSettings,
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
      _logger.i('FCM Token obtained (${token.length} chars)');

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
    _logger.i('FCM Token refreshed (${newToken.length} chars)');
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
    final senderId = message.data['senderId'] as String?;

    // Safety: suppress notifications for the user's own messages.
    // The Cloud Function already skips the sender, but this is a client-side
    // safety net in case of race conditions or stale FCM token mappings.
    if (senderId != null && senderId == _currentUserId) {
      _logger.d('Suppressing notification for own message (senderId=$senderId)');
      return;
    }

    // Check if user is viewing the conversation that received a message
    final isViewingConversation = messageType == 'message' &&
        messageConversationId != null &&
        messageConversationId == _currentConversationId;

    // Check if user is viewing the group chat that received a message
    // Must check all group message types: location, nearby, and random
    final isGroupMessageType = messageType == 'group_message' ||
        messageType == 'nearby_group_message' ||
        messageType == 'random_group_message';
    final isViewingGroupChat = isGroupMessageType &&
        messageGroupId != null &&
        messageGroupId == _currentGroupId;

    if (isViewingConversation) {
      // User is viewing this chat - don't show any notification
      _logger.d(
          'Suppressing notification: user is viewing conversation '
          '$messageConversationId (currentConversationId=$_currentConversationId)');
      return;
    }

    if (isViewingGroupChat) {
      // User is viewing this group chat - don't show any notification
      _logger.d(
          'Suppressing notification: user is viewing group '
          '$messageGroupId (currentGroupId=$_currentGroupId)');
      return;
    }

    _logger.d(
      'Showing notification: type=$messageType, '
      'convId=$messageConversationId, groupId=$messageGroupId, '
      'currentConv=$_currentConversationId, currentGroup=$_currentGroupId',
    );

    // User is not viewing this chat - show in-app notification
    if (notification != null) {
      // Show in-app notification (SnackBar) if callback is registered.
      // Supports DMs and all group message types so users see a banner
      // regardless of which chat type the message belongs to.
      final isInAppType = messageType == 'message' ||
          messageType == 'group_message' ||
          messageType == 'nearby_group_message' ||
          messageType == 'random_group_message';
      if (onInAppNotification != null && isInAppType) {
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

      // Generate a deterministic notification ID from the conversation/group ID
      // so that multiple messages from the same sender replace each other
      // instead of cluttering the notification panel.
      final String? sourceId = messageConversationId ?? messageGroupId;
      final int notificationId = sourceId != null
          ? sourceId.hashCode & 0x7FFFFFFF // ensure positive int
          : notification.hashCode;

      // Determine Android groupKey for visual notification grouping
      final String? groupKey = sourceId != null ? 'radius_$sourceId' : null;

      // Track the notification ID for later cancellation
      if (sourceId != null) {
        _activeNotificationIds
            .putIfAbsent(sourceId, () => {})
            .add(notificationId);
      }

      // Also show system notification banner
      // Using Importance.max and Priority.max for heads-up notifications
      await _localNotifications.show(
        id: notificationId,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
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
            // Group notifications from the same conversation/sender
            groupKey: groupKey,
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
  /// This prevents showing notifications for messages in this conversation
  /// and clears any existing notifications for it from the device panel.
  void setCurrentConversation(String? conversationId) {
    _currentConversationId = conversationId;
    if (conversationId != null) {
      _cancelNotificationsForSource(conversationId);
    }
    _logger.d('Current conversation set to: $conversationId');
  }

  /// Clear the current conversation (user left the chat screen).
  ///
  /// Accepts an optional [conversationId] to prevent race conditions:
  /// when navigating between chats, the old screen's dispose() might run
  /// AFTER the new screen's initState(), which would incorrectly clear
  /// the conversation ID that the new screen just set.
  ///
  /// If [conversationId] is provided, only clears if it matches the current one.
  /// If null, always clears (legacy behavior).
  void clearCurrentConversation([String? conversationId]) {
    if (conversationId != null && _currentConversationId != conversationId) {
      _logger.d(
        'Skipping clearCurrentConversation: current=$_currentConversationId, '
        'requested=$conversationId (another chat is active)',
      );
      return;
    }
    _logger.d('Current conversation cleared (was: $_currentConversationId)');
    _currentConversationId = null;
  }

  /// Set the current group the user is viewing.
  /// This prevents showing notifications for messages in this group
  /// and clears any existing notifications for it from the device panel.
  void setCurrentGroup(String? groupId) {
    _currentGroupId = groupId;
    if (groupId != null) {
      _cancelNotificationsForSource(groupId);
    }
    _logger.d('Current group set to: $groupId');
  }

  /// Clear the current group (user left the group chat screen).
  ///
  /// Accepts an optional [groupId] to prevent race conditions:
  /// when navigating between group chats, the old screen's dispose() might
  /// run AFTER the new screen's initState(), which would incorrectly clear
  /// the group ID that the new screen just set.
  ///
  /// If [groupId] is provided, only clears if it matches the current one.
  /// If null, always clears (legacy behavior).
  void clearCurrentGroup([String? groupId]) {
    if (groupId != null && _currentGroupId != groupId) {
      _logger.d(
        'Skipping clearCurrentGroup: current=$_currentGroupId, '
        'requested=$groupId (another group chat is active)',
      );
      return;
    }
    _logger.d('Current group cleared (was: $_currentGroupId)');
    _currentGroupId = null;
  }

  /// Cancel all device notifications for a given conversation or group ID.
  Future<void> _cancelNotificationsForSource(String sourceId) async {
    final ids = _activeNotificationIds.remove(sourceId);
    if (ids != null && ids.isNotEmpty) {
      for (final id in ids) {
        await _localNotifications.cancel(id: id);
      }
      _logger
          .d('Cancelled ${ids.length} notification(s) for source: $sourceId');
    }
    // Also cancel by deterministic ID in case tracked set was lost (e.g. app restart)
    final deterministicId = sourceId.hashCode & 0x7FFFFFFF;
    await _localNotifications.cancel(id: deterministicId);
  }

  /// Remove FCM token on sign out.
  Future<void> removeToken() async {
    if (_currentUserId == null || _fcmToken == null) return;

    try {
      await _firestore.collection('users').doc(_currentUserId).update({
        'fcmTokens.$_fcmToken': FieldValue.delete(),
      });
    } catch (e) {
      _logger.e('Error removing FCM token from Firestore', error: e);
    }

    try {
      await _messaging.deleteToken();
    } catch (e) {
      // FIS_AUTH_ERROR is expected if called after Firebase Auth sign-out
      _logger.d('Could not delete FCM token (expected during sign-out)', error: e);
    }

    _fcmToken = null;
    _currentUserId = null;
    _logger.i('FCM token cleanup complete');
  }
}

/// Background message handler (must be top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized.
  // Required on iOS when the app is terminated and a data-only message
  // arrives — without this, Firestore and other Firebase calls would fail.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized — safe to ignore.
  }

  debugPrint('Background message: ${message.notification?.title}');
}
