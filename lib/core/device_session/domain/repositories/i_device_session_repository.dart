import '../entities/device_session.dart';

/// Repository interface for managing device session data.
abstract class IDeviceSessionRepository {
  /// Save a device session to Firestore
  Future<void> saveDeviceSession(DeviceSession session);

  /// Get device sessions for a specific user
  Future<List<DeviceSession>> getUserSessions(String userId);
}
