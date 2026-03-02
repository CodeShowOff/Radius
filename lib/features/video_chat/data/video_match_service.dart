import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

/// Manages the random video-chat matching queue in Firestore.
///
/// Collection: `video_chat_queue/{userId}`
///
/// Flow:
/// 1. User joins queue → writes doc with status `waiting`.
/// 2. Immediately queries for another `waiting` user (excluding self).
/// 3. If found, a Firestore **transaction** atomically marks both docs as
///    `matched`, recording each other's info and assigning caller/receiver roles.
/// 4. Each side listens to its own queue doc — when `status == matched`,
///    the caller creates the WebRTC call and the receiver waits for it.
class VideoMatchService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  VideoMatchService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger();

  CollectionReference<Map<String, dynamic>> get _queueRef =>
      _firestore.collection('video_chat_queue');

  // ════════════════════════════════════════════════════════════════════
  //  Join / Leave Queue
  // ════════════════════════════════════════════════════════════════════

  /// Adds the user to the matching queue with status `waiting`.
  Future<void> joinQueue({
    required String userId,
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      await _queueRef.doc(userId).set({
        'userId': userId,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'status': 'waiting',
        'matchedWith': null,
        'matchedName': null,
        'matchedPhotoUrl': null,
        'callRole': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _logger.d('Joined video chat queue: $userId');
    } catch (e, st) {
      _logger.e('Failed to join queue', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Removes the user from the queue (cancel search or cleanup).
  Future<void> leaveQueue(String userId) async {
    try {
      await _queueRef.doc(userId).delete();
      _logger.d('Left video chat queue: $userId');
    } catch (e) {
      _logger.w('Failed to leave queue: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Matching
  // ════════════════════════════════════════════════════════════════════

  /// Attempts to find and match with another waiting user.
  ///
  /// Uses a Firestore transaction so that two concurrent searchers cannot
  /// both claim the same waiting user. Returns `true` if a match was made.
  Future<bool> tryMatch({
    required String myUserId,
    required String myDisplayName,
    String? myPhotoUrl,
  }) async {
    try {
      // Find a single other user who is still waiting.
      final snapshot = await _queueRef
          .where('status', isEqualTo: 'waiting')
          .limit(5) // grab a small batch to tolerate stale docs
          .get();

      // Filter out self.
      final candidates =
          snapshot.docs.where((d) => d.id != myUserId).toList();

      if (candidates.isEmpty) return false;

      // Try each candidate in a transaction — first success wins.
      for (final candidate in candidates) {
        final success = await _firestore.runTransaction<bool>((txn) async {
          final freshDoc = await txn.get(_queueRef.doc(candidate.id));
          if (!freshDoc.exists) return false;
          final data = freshDoc.data()!;
          if (data['status'] != 'waiting') return false;

          // Also re-check our own doc is still 'waiting'.
          final myDoc = await txn.get(_queueRef.doc(myUserId));
          if (!myDoc.exists || myDoc.data()?['status'] != 'waiting') {
            return false;
          }

          final otherUserId = candidate.id;
          final otherName = data['displayName'] as String? ?? 'Anonymous';
          final otherPhoto = data['photoUrl'] as String?;

          // Mark BOTH as matched.
          txn.update(_queueRef.doc(myUserId), {
            'status': 'matched',
            'matchedWith': otherUserId,
            'matchedName': otherName,
            'matchedPhotoUrl': otherPhoto,
            'callRole': 'caller', // I found the match → I create the offer.
          });
          txn.update(_queueRef.doc(otherUserId), {
            'status': 'matched',
            'matchedWith': myUserId,
            'matchedName': myDisplayName,
            'matchedPhotoUrl': myPhotoUrl,
            'callRole': 'receiver',
          });

          return true;
        });

        if (success) {
          _logger.d('Matched $myUserId with ${candidate.id}');
          return true;
        }
      }

      return false;
    } catch (e, st) {
      _logger.e('Match attempt failed', error: e, stackTrace: st);
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  //  Real-time Listener
  // ════════════════════════════════════════════════════════════════════

  /// Watches the current user's queue document for status changes.
  ///
  /// Emits a map with `status`, `matchedWith`, `matchedName`,
  /// `matchedPhotoUrl`, `callRole` whenever the document updates.
  /// Emits `null` when the document is deleted / does not exist.
  Stream<Map<String, dynamic>?> watchMyQueueDoc(String userId) {
    return _queueRef.doc(userId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return snap.data()!;
    });
  }
}
