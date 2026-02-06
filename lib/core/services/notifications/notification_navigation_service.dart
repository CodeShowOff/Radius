import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logger/logger.dart';

import '../../router/app_router.dart';
import '../../router/routes.dart';

/// Service for handling notification navigation (deep linking).
///
/// Handles navigation when:
/// - App is opened from a notification tap (background/terminated state)
/// - Notification is tapped while app is in foreground
/// - Deep links from notifications
class NotificationNavigationService {
  final FirebaseMessaging _messaging;
  final Logger _logger;
  
  bool _initialized = false;

  NotificationNavigationService({
    FirebaseMessaging? messaging,
    Logger? logger,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _logger = logger ?? Logger();

  /// Initialize the service to handle notification navigation.
  /// Should be called after the router is ready.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Handle notification tap when app was terminated
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _logger.i('App opened from terminated state via notification');
      // Delay navigation slightly to ensure router is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationNavigation(initialMessage);
      });
    }

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logger.i('App opened from background via notification');
      _handleNotificationNavigation(message);
    });
  }

  /// Handle navigation based on notification data.
  void _handleNotificationNavigation(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;
    
    _logger.i('Handling notification navigation: type=$type, data=$data');

    if (type == null) {
      _logger.w('No notification type found in data');
      return;
    }

    try {
      switch (type) {
        case 'message':
          _navigateToChat(data);
          break;
        case 'group_message':
          _navigateToGroupChat(data);
          break;
        case 'nearby_group_message':
          _navigateToNearbyGroupChat(data);
          break;
        case 'random_group_message':
          _navigateToRandomGroupChat(data);
          break;
        case 'connection_request':
          _navigateToConnectionRequests();
          break;
        case 'nearby_help_request':
          _navigateToHelpRequest(data);
          break;
        case 'nearby_help_assigned':
          _navigateToHelpRequestDetail(data);
          break;
        case 'nearby_help_completed':
        case 'nearby_help_cancelled':
        case 'nearby_help_expired':
          _navigateToNearbyHelp();
          break;
        default:
          _logger.w('Unknown notification type: $type');
      }
    } catch (e, stack) {
      _logger.e('Error navigating from notification', error: e, stackTrace: stack);
    }
  }

  /// Navigate to chat screen.
  void _navigateToChat(Map<String, dynamic> data) {
    final conversationId = data['conversationId'] as String?;
    if (conversationId == null) {
      _logger.w('No conversationId in notification data');
      return;
    }

    appRouter.push(Routes.chatWith(conversationId));
  }

  /// Navigate to group chat screen.
  void _navigateToGroupChat(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    if (groupId == null) {
      _logger.w('No groupId in notification data');
      return;
    }

    // Determine which type of group it is and navigate accordingly
    // For now, default to location groups
    appRouter.push(Routes.locationGroupChatWith(groupId));
  }

  /// Navigate to nearby group chat screen.
  void _navigateToNearbyGroupChat(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    if (groupId == null) {
      _logger.w('No groupId in nearby group notification data');
      return;
    }

    _logger.i('Navigating to nearby group chat: $groupId');
    appRouter.push(Routes.nearbyGroupChatWith(groupId));
  }

  /// Navigate to random group chat screen.
  void _navigateToRandomGroupChat(Map<String, dynamic> data) {
    final groupId = data['groupId'] as String?;
    if (groupId == null) {
      _logger.w('No groupId in random group notification data');
      return;
    }

    _logger.i('Navigating to random group chat: $groupId');
    appRouter.push(Routes.randomGroupChatWith(groupId));
  }

  /// Navigate to connection requests screen.
  void _navigateToConnectionRequests() {
    appRouter.push(Routes.connectionRequests);
  }

  /// Navigate to incoming help requests page with the specific request highlighted.
  void _navigateToHelpRequest(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;

    if (requestId != null) {
      // Navigate to incoming requests with the request highlighted,
      // which will then navigate to the request detail with confirmation
      appRouter.push(Routes.nearbyHelpIncomingRequestsWith(highlightRequestId: requestId));
    } else {
      // If no specific request, just go to incoming requests
      appRouter.push(Routes.nearbyHelpIncomingRequests);
    }
  }

  /// Navigate directly to help request detail page with confirmation prompt.
  /// This is used when a helper has been assigned and needs to confirm acceptance.
  void _navigateToHelpRequestDetail(Map<String, dynamic> data) {
    final requestId = data['requestId'] as String?;

    if (requestId != null) {
      // Add query parameter to trigger confirmation dialog
      appRouter.push('${Routes.nearbyHelpRequestDetailWith(requestId)}?confirmAcceptance=true');
    } else {
      // Fallback to nearby help main page
      appRouter.push(Routes.nearbyHelp);
    }
  }

  /// Navigate to nearby help main page.
  void _navigateToNearbyHelp() {
    appRouter.push(Routes.nearbyHelp);
  }

  /// Parse notification payload from local notification tap.
  /// 
  /// Format: "type|id" or just "id" for backwards compatibility
  void handleLocalNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;

    _logger.i('Handling local notification payload: $payload');

    final parts = payload.split('|');
    if (parts.length >= 2) {
      final type = parts[0];
      final id = parts[1];

      switch (type) {
        case 'message':
          appRouter.push(Routes.chatWith(id));
          break;
        case 'group_message':
          appRouter.push(Routes.locationGroupChatWith(id));
          break;
        case 'nearby_group_message':
          appRouter.push(Routes.nearbyGroupChatWith(id));
          break;
        case 'random_group_message':
          appRouter.push(Routes.randomGroupChatWith(id));
          break;
        case 'connection_request':
          appRouter.push(Routes.connectionRequests);
          break;
        case 'nearby_help_request':
          appRouter.push(Routes.nearbyHelpIncomingRequestsWith(highlightRequestId: id));
          break;
        case 'nearby_help_assigned':
          // Add confirmation query parameter
          appRouter.push('${Routes.nearbyHelpRequestDetailWith(id)}?confirmAcceptance=true');
          break;
        case 'nearby_help_completed':
        case 'nearby_help_cancelled':
        case 'nearby_help_expired':
          appRouter.push(Routes.nearbyHelpRequestDetailWith(id));
          break;
        default:
          _logger.w('Unknown payload type: $type');
      }
    } else {
      // Legacy format: just the ID (assume it's a conversation ID)
      appRouter.push(Routes.chatWith(payload));
    }
  }
}
