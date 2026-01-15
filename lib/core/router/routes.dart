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
  
  // Main app routes
  static const String home = '/home';
  static const String nearby = '/nearby';
  static const String profile = '/profile';
  static const String editProfile = '/profile/edit';
  
  // Connection routes
  static const String connections = '/connections';
  static const String connectionRequests = '/connections/requests';
  static const String connectionDetails = '/connection/:id';
  
  // Chat routes
  static const String conversations = '/conversations';
  static const String chat = '/chat/:conversationId';
  
  /// Helper to build a chat route with conversation ID.
  static String chatWith(String conversationId) => '/chat/$conversationId';
  
  // Settings routes
  static const String settings = '/settings';
  static const String bluetoothSettings = '/settings/bluetooth';
  static const String privacySettings = '/settings/privacy';
}
