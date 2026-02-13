/// Centralized route paths for the application.
///
/// All route strings are defined here to avoid magic strings
/// and enable easy refactoring.
abstract class Routes {
  // Initial routes
  static const String splash = '/';

  // Authentication routes
  static const String login = '/login';
  static const String register = '/register';
  static const String emailVerification = '/verify-email';

  // Main app routes
  static const String home = '/home';
  static const String nearby = '/nearby';
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';

  // Connection routes
  static const String connections = '/connections';
  static const String connectionRequests = '/connections/requests';
  static const String connectionDetails = '/connection/:id';

  // Discovery routes (username-based user search & connection)
  static const String discoverySearch = '/discovery/search';
  static const String discoveryRequests = '/discovery/requests';

    // User profile (other user) routes
    static const String userProfile = '/users/:userId';

    /// Helper to build a user profile route with user ID.
    static String userProfileWith(String userId) => '/users/$userId';

  // Chat routes
  static const String conversations = '/conversations';
  static const String chat = '/chat/:conversationId';

  /// Helper to build a chat route with conversation ID.
  static String chatWith(String conversationId) => '/chat/$conversationId';

  // Settings routes
  static const String settings = '/settings';
  static const String bluetoothSettings = '/settings/bluetooth';
  static const String locationSettings = '/settings/location';
  static const String appearanceSettings = '/settings/appearance';
  static const String notificationSettings = '/settings/notifications';
  static const String diagnosticsLogs = '/settings/diagnostics-logs';
  static const String privacySettings = '/settings/privacy';
  static const String helpSupport = '/help-support';

  // Location Groups routes
  static const String locationGroups = '/location-groups';
  static const String myGroups = '/my-groups';
  static const String createLocationGroup = '/location-groups/create';
  static const String locationGroupDetail = '/location-groups/:groupId';
  static const String locationGroupChat = '/location-groups/:groupId/chat';

  /// Helper to build a group detail route with group ID.
  static String locationGroupDetailWith(String groupId) =>
      '/location-groups/$groupId';

  /// Helper to build a group chat route with group ID.
  static String locationGroupChatWith(String groupId) =>
      '/location-groups/$groupId/chat';

  // Nearby Groups routes (Bluetooth-based proximity groups)
  static const String nearbyGroups = '/nearby-groups';
  static const String discoverNearbyGroups = '/nearby-groups/discover';
  static const String createNearbyGroup = '/nearby-groups/create';
  static const String nearbyGroupChat = '/nearby-groups/:groupId/chat';

  /// Helper to build a nearby group chat route with group ID.
  static String nearbyGroupChatWith(String groupId) =>
      '/nearby-groups/$groupId/chat';

  // Random Groups routes (Admin-approved internet-based groups)
  static const String randomGroups = '/random-groups';
  static const String discoverRandomGroups = '/random-groups/discover';
  static const String createRandomGroup = '/random-groups/create';
  static const String randomGroupDetail = '/random-groups/:groupId';
  static const String randomGroupSettings = '/random-groups/:groupId/settings';
  static const String randomGroupChat = '/random-groups/:groupId/chat';

  /// Helper to build a random group detail route with group ID.
  static String randomGroupDetailWith(String groupId) =>
      '/random-groups/$groupId';

  /// Helper to build a random group settings route with group ID.
  static String randomGroupSettingsWith(String groupId) =>
      '/random-groups/$groupId/settings';

  /// Helper to build a random group chat route with group ID.
  static String randomGroupChatWith(String groupId) =>
      '/random-groups/$groupId/chat';

  // Nearby Help routes
  static const String nearbyHelp = '/nearby-help';
  static const String nearbyHelpSettings = '/nearby-help/settings';
  static const String nearbyHelpCreateRequest = '/nearby-help/create';
  static const String nearbyHelpIncomingRequests = '/nearby-help/incoming';
  static const String nearbyHelpRequestDetail = '/nearby-help/request/:requestId';
  static const String nearbyHelpHelperNavigation = '/nearby-help/navigate/:requestId';

  // Random Chat routes (daily random user discovery & chat)
  static const String randomChat = '/random-chat';

  /// Helper to build a help request detail route with request ID.
  static String nearbyHelpRequestDetailWith(String requestId) =>
      '/nearby-help/request/$requestId';

  /// Helper to build a helper navigation route with request ID.
  static String nearbyHelpHelperNavigationWith(String requestId) =>
      '/nearby-help/navigate/$requestId';

  /// Helper to build an incoming requests route with optional highlight request ID.
  static String nearbyHelpIncomingRequestsWith({String? highlightRequestId}) {
    if (highlightRequestId != null) {
      return '/nearby-help/incoming?requestId=$highlightRequestId';
    }
    return '/nearby-help/incoming';
  }
}
