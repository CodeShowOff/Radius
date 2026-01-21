import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/profile/data/models/profile_model.dart';

/// Service for profile-related Firestore operations.
/// Now uses ONLY the 'users' collection - profiles collection removed.
/// Consistent field names: photoUrl (not avatarUrl), displayName (not name)
class ProfileService {
  final FirebaseFirestore _firestore;

  static const String _usersCollection = 'users';

  ProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Reference to users collection - the single source of truth.
  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection(_usersCollection);

  /// Gets a profile by user ID.
  Future<ProfileModel?> getProfile(String userId) async {
    try {
      final doc = await _usersRef.doc(userId).get();
      if (!doc.exists) return null;
      return ProfileModel.fromFirestore(doc);
    } catch (e) {
      throw ProfileServiceException('Failed to get profile: $e');
    }
  }

  /// Creates a new profile.
  Future<void> createProfile(ProfileModel profile) async {
    try {
      final userRef = _usersRef.doc(profile.userId);
      final profileData = profile.toFirestore();
      
      await userRef.set(profileData, SetOptions(merge: true));
    } catch (e) {
      throw ProfileServiceException('Failed to create profile: $e');
    }
  }

  /// Updates an existing profile.
  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      final userRef = _usersRef.doc(userId);
      await userRef.update(data);
    } catch (e) {
      throw ProfileServiceException('Failed to update profile: $e');
    }
  }

  /// Updates profile photo URL.
  Future<void> updateProfilePhoto(String userId, String photoUrl) async {
    try {
      final userRef = _usersRef.doc(userId);
      
      await userRef.update({
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ProfileServiceException('Failed to update profile photo: $e');
    }
  }

  /// Updates visibility status.
  Future<void> updateVisibility(String userId, bool isVisible) async {
    try {
      final userRef = _usersRef.doc(userId);
      
      await userRef.update({
        'isVisible': isVisible,
        'isDiscoverable': isVisible,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw ProfileServiceException('Failed to update visibility: $e');
    }
  }

  /// Deletes a profile.
  Future<void> deleteProfile(String userId) async {
    try {
      await _usersRef.doc(userId).delete();
    } catch (e) {
      throw ProfileServiceException('Failed to delete profile: $e');
    }
  }

  /// Streams profile changes in real-time.
  Stream<ProfileModel?> profileStream(String userId) {
    return _usersRef.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ProfileModel.fromFirestore(doc);
    });
  }

  /// Gets all visible profiles (for discovery).
  Future<List<ProfileModel>> getVisibleProfiles({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _usersRef
          .where('isVisible', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => ProfileModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw ProfileServiceException('Failed to get visible profiles: $e');
    }
  }

  /// Checks if a profile exists.
  Future<bool> profileExists(String userId) async {
    try {
      final doc = await _usersRef.doc(userId).get();
      return doc.exists;
    } catch (e) {
      throw ProfileServiceException('Failed to check profile existence: $e');
    }
  }
}

/// Exception for profile service errors.
class ProfileServiceException implements Exception {
  final String message;
  const ProfileServiceException(this.message);

  @override
  String toString() => 'ProfileServiceException: $message';
}
