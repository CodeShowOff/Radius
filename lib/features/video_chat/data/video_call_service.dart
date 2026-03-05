import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../domain/entities/call_status.dart';
import '../domain/entities/video_call.dart';

/// Service for managing video call signaling through Firestore.
///
/// Handles creation, answering, ending of calls, and real-time listening
/// for call status changes and ICE candidate exchange.
class VideoCallService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  VideoCallService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  /// Top-level collection for video calls.
  CollectionReference<Map<String, dynamic>> get _callsRef =>
      _firestore.collection('video_calls');

  // ════════════════════════════════════════════════════════════════════
  //  Call Lifecycle
  // ════════════════════════════════════════════════════════════════════

  /// Creates a new video call document with an SDP offer.
  ///
  /// Returns the auto-generated call document ID.
  Future<String> createCall({
    required String callerId,
    required String callerName,
    String? callerPhotoUrl,
    required String receiverId,
    required String receiverName,
    String? receiverPhotoUrl,
    required Map<String, dynamic> offer,
  }) async {
    try {
      final doc = _callsRef.doc();
      final callData = {
        'callerId': callerId,
        'callerName': callerName,
        'callerPhotoUrl': callerPhotoUrl,
        'receiverId': receiverId,
        'receiverName': receiverName,
        'receiverPhotoUrl': receiverPhotoUrl,
        'status': CallStatus.ringing.toFirestore(),
        'offer': offer,
        'answer': null,
        'createdAt': DateTime.now().toIso8601String(),
        'answeredAt': null,
        'endedAt': null,
      };

      await doc.set(callData);
      _logger.d('Video call created: ${doc.id}');
      return doc.id;
    } catch (e, st) {
      _logger.e('Failed to create video call', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Updates a call with the SDP answer and sets status to connecting.
  Future<void> answerCall({
    required String callId,
    required Map<String, dynamic> answer,
  }) async {
    try {
      await _callsRef.doc(callId).update({
        'answer': answer,
        'status': CallStatus.connecting.toFirestore(),
        'answeredAt': DateTime.now().toIso8601String(),
      });
      _logger.d('Video call answered: $callId');
    } catch (e, st) {
      _logger.e('Failed to answer call', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Updates the call status to connected (media is flowing).
  Future<void> markConnected(String callId) async {
    try {
      await _callsRef.doc(callId).update({
        'status': CallStatus.connected.toFirestore(),
      });
    } catch (e) {
      _logger.w('Failed to mark call connected: $e');
    }
  }

  /// Ends a call (normal hangup).
  Future<void> endCall(String callId) async {
    try {
      await _callsRef.doc(callId).update({
        'status': CallStatus.ended.toFirestore(),
        'endedAt': DateTime.now().toIso8601String(),
      });
      _logger.d('Video call ended: $callId');
    } catch (e, st) {
      _logger.e('Failed to end call', error: e, stackTrace: st);
    }
  }

  /// Updates the offer in Firestore (used for ICE restart).
  Future<void> updateOffer({
    required String callId,
    required Map<String, dynamic> offer,
  }) async {
    try {
      await _callsRef.doc(callId).update({
        'offer': offer,
        'status': CallStatus.connecting.toFirestore(),
      });
      _logger.d('Updated offer for ICE restart: $callId');
    } catch (e, st) {
      _logger.e('Failed to update offer', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Declines an incoming call.
  Future<void> declineCall(String callId) async {
    try {
      await _callsRef.doc(callId).update({
        'status': CallStatus.declined.toFirestore(),
        'endedAt': DateTime.now().toIso8601String(),
      });
      _logger.d('Video call declined: $callId');
    } catch (e, st) {
      _logger.e('Failed to decline call', error: e, stackTrace: st);
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  ICE Candidates
  // ════════════════════════════════════════════════════════════════════

  /// Adds an ICE candidate to the call's candidates subcollection.
  Future<void> addIceCandidate({
    required String callId,
    required String from,
    required Map<String, dynamic> candidate,
  }) async {
    try {
      await _callsRef.doc(callId).collection('candidates').add({
        'from': from,
        'candidate': candidate['candidate'],
        'sdpMid': candidate['sdpMid'],
        'sdpMLineIndex': candidate['sdpMLineIndex'],
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.w('Failed to add ICE candidate: $e');
    }
  }

  /// Watches ICE candidates from the other peer.
  ///
  /// Filters candidates where `from != myUserId` to only get the
  /// other peer's candidates.
  Stream<List<Map<String, dynamic>>> watchIceCandidates({
    required String callId,
    required String myUserId,
  }) {
    return _callsRef
        .doc(callId)
        .collection('candidates')
        .where('from', isNotEqualTo: myUserId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docChanges
          .where((change) => change.type == DocumentChangeType.added)
          .map((change) => change.doc.data()!)
          .toList();
    });
  }

  // ════════════════════════════════════════════════════════════════════
  //  Real-time Listeners
  // ════════════════════════════════════════════════════════════════════

  /// Watches a specific call document for status changes.
  Stream<VideoCall?> watchCall(String callId) {
    return _callsRef.doc(callId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return VideoCall.fromJson(doc.id, doc.data()!);
    });
  }

  /// Watches for incoming calls (calls where current user is the receiver
  /// and status is 'ringing').
  ///
  /// If [fromCallerId] is provided, only calls from that caller are watched.
  Stream<VideoCall?> watchIncomingCalls(
    String userId, {
    String? fromCallerId,
  }) {
    Query<Map<String, dynamic>> query = _callsRef
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: CallStatus.ringing.toFirestore());

    if (fromCallerId != null && fromCallerId.isNotEmpty) {
      query = query.where('callerId', isEqualTo: fromCallerId);
    }

    return query.limit(1).snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      return VideoCall.fromJson(doc.id, doc.data());
    });
  }

  // ════════════════════════════════════════════════════════════════════
  //  Cleanup
  // ════════════════════════════════════════════════════════════════════

  /// Deletes all ICE candidates and the call document.
  /// Called after a call ends to clean up ephemeral signaling data.
  Future<void> cleanupCall(String callId) async {
    try {
      // Delete candidates subcollection
      final candidates =
          await _callsRef.doc(callId).collection('candidates').get();
      final batch = _firestore.batch();
      for (final doc in candidates.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_callsRef.doc(callId));
      await batch.commit();
      _logger.d('Video call cleaned up: $callId');
    } catch (e) {
      _logger.w('Failed to cleanup call $callId: $e');
    }
  }
}
