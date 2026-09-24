/// Environment variables and configuration constants
abstract class Env {
  /// The base URL for the backend API.
  /// Can be overridden at compile time using: --dart-define=BACKEND_URL=http://your-ip:3000/api
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://radius-backend-zr84.onrender.com/api',
  );
  
  /// The endpoint URL for media uploads.
  static const String uploadUrl = '$backendUrl/upload';
}
