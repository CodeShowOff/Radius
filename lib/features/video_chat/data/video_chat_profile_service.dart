import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';

import '../domain/entities/video_chat_profile.dart';

/// Service for managing anonymous video chat profiles in Firestore.
///
/// Profiles are stored in `video_chat_profiles/{userId}` and are
/// completely separate from the user's real Radius profile.
class VideoChatProfileService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Logger _logger;

  VideoChatProfileService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _logger = logger ?? Logger();

  /// Collection reference for video chat profiles.
  CollectionReference<Map<String, dynamic>> get _profilesRef =>
      _firestore.collection('video_chat_profiles');

  // ════════════════════════════════════════════════════════════════════
  //  Profile CRUD
  // ════════════════════════════════════════════════════════════════════

  /// Fetches the anonymous video chat profile for the given [userId].
  /// Returns `null` if no profile exists yet (first time user).
  Future<VideoChatProfile?> getProfile(String userId) async {
    try {
      final doc = await _profilesRef.doc(userId).get();
      if (!doc.exists || doc.data() == null) return null;
      return VideoChatProfile.fromJson(doc.data()!);
    } catch (e, st) {
      _logger.e('Failed to fetch video chat profile', error: e, stackTrace: st);
      return null;
    }
  }

  /// Creates or updates the anonymous video chat profile.
  Future<void> saveProfile(VideoChatProfile profile) async {
    try {
      await _profilesRef.doc(profile.userId).set(
        profile.toJson(),
        SetOptions(merge: true),
      );
      _logger.d('Video chat profile saved for ${profile.userId}');
    } catch (e, st) {
      _logger.e('Failed to save video chat profile', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Uploads a profile photo to Firebase Storage and returns the download URL.
  ///
  /// Photos are stored at `video_chat_photos/{userId}/profile.jpg`.
  /// Each upload overwrites the previous photo (only one photo per user).
  Future<String> uploadProfilePhoto({
    required String userId,
    required String filePath,
  }) async {
    try {
      final ref = _storage.ref('video_chat_photos/$userId/profile.jpg');
      final file = File(filePath);
      final ext = filePath.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'png' => 'image/png',
        'heic' || 'heif' => 'image/heic',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: contentType),
      );
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      _logger.d('Video chat profile photo uploaded for $userId');
      return url;
    } catch (e, st) {
      _logger.e('Failed to upload profile photo', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// Deletes the profile photo from Firebase Storage.
  Future<void> deleteProfilePhoto(String userId) async {
    try {
      final ref = _storage.ref('video_chat_photos/$userId/profile.jpg');
      await ref.delete();
      _logger.d('Video chat profile photo deleted for $userId');
    } catch (e) {
      // Ignore — file may not exist
      _logger.w('Could not delete profile photo: $e');
    }
  }
}
