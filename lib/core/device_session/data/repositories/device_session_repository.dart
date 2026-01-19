import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/device_session.dart';
import '../../domain/repositories/i_device_session_repository.dart';
import '../models/device_session_model.dart';

/// Implementation of [IDeviceSessionRepository] using Firestore.
@LazySingleton(as: IDeviceSessionRepository)
class DeviceSessionRepository implements IDeviceSessionRepository {
  final FirebaseFirestore _firestore;

  DeviceSessionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collectionName = 'device_sessions';

  @override
  Future<void> saveDeviceSession(DeviceSession session) async {
    try {
      final model = DeviceSessionModel.fromEntity(session);
      await _firestore
          .collection(_collectionName)
          .doc(session.sessionId)
          .set(model.toFirestore());
    } catch (e) {
      // Log error but don't fail the authentication flow
      // In production, this should be logged to crash reporting
      // ignore: avoid_print
      print('Error saving device session: $e');
    }
  }

  @override
  Future<List<DeviceSession>> getUserSessions(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collectionName)
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(50) // Limit to last 50 sessions
          .get();

      return querySnapshot.docs
          .map((doc) => DeviceSessionModel.fromFirestore(doc).toEntity())
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching user sessions: $e');
      return [];
    }
  }
}
