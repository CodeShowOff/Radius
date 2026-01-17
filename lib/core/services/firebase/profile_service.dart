import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/profile/data/models/profile_model.dart';

/// Service for profile-related Firestore operations.
class ProfileService {
  final FirebaseFirestore _firestore;

  static const String _collection = 'profiles';
  static const String _usersCollection = 'users';

  ProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Reference to profiles collection.
  CollectionReference<Map<String, dynamic>> get _profilesRef =>
      _firestore.collection(_collection);

  /// Reference to users collection (auth/profile canonical fields).
  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection(_usersCollection);

  Map<String, dynamic> _userSyncFromProfileData(Map<String, dynamic> data) {
    final sync = <String, dynamic>{};

    if (data.containsKey('name')) sync['displayName'] = data['name'];
    if (data.containsKey('bio')) sync['bio'] = data['bio'];
    if (data.containsKey('photoUrl')) sync['avatarUrl'] = data['photoUrl'];
    if (data.containsKey('isVisible')) {
      sync['isDiscoverable'] = data['isVisible'];
    }

    return sync;
  }

  /// Gets a profile by user ID.
  Future<ProfileModel?> getProfile(String userId) async {
    try {
      final doc = await _profilesRef.doc(userId).get();
      if (!doc.exists) return null;
      return ProfileModel.fromFirestore(doc);
    } catch (e) {
      throw ProfileServiceException('Failed to get profile: $e');
    }
  }

  /// Creates a new profile.
  Future<void> createProfile(ProfileModel profile) async {
    try {
      final batch = _firestore.batch();
      final profileRef = _profilesRef.doc(profile.userId);
      final userRef = _usersRef.doc(profile.userId);

      final profileData = profile.toFirestore();
      batch.set(profileRef, profileData);

      // Keep users/{userId} in sync for features that read from `users`.
      batch.set(
        userRef,
        {
          'displayName': profile.name,
          'avatarUrl': profile.photoUrl,
          'bio': profile.bio,
          'isDiscoverable': profile.isVisible,
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e) {
      throw ProfileServiceException('Failed to create profile: $e');
    }
  }

  /// Updates an existing profile.
  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      final batch = _firestore.batch();
      final profileRef = _profilesRef.doc(userId);
      final userRef = _usersRef.doc(userId);

      batch.update(profileRef, data);

      final sync = _userSyncFromProfileData(data);
      if (sync.isNotEmpty) {
        batch.set(userRef, sync, SetOptions(merge: true));
      }

      await batch.commit();
    } catch (e) {
      throw ProfileServiceException('Failed to update profile: $e');
    }
  }

  /// Updates profile photo URL.
  Future<void> updateProfilePhoto(String userId, String photoUrl) async {
    try {
      final batch = _firestore.batch();
      final profileRef = _profilesRef.doc(userId);
      final userRef = _usersRef.doc(userId);

      batch.update(profileRef, {
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(userRef, {'avatarUrl': photoUrl}, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      throw ProfileServiceException('Failed to update profile photo: $e');
    }
  }

  /// Updates visibility status.
  Future<void> updateVisibility(String userId, bool isVisible) async {
    try {
      final batch = _firestore.batch();
      final profileRef = _profilesRef.doc(userId);
      final userRef = _usersRef.doc(userId);

      batch.update(profileRef, {
        'isVisible': isVisible,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Keep users/{userId} discoverability in sync for legacy/other features.
      batch.set(
        userRef,
        {'isDiscoverable': isVisible},
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e) {
      throw ProfileServiceException('Failed to update visibility: $e');
    }
  }

  /// Deletes a profile.
  Future<void> deleteProfile(String userId) async {
    try {
      await _profilesRef.doc(userId).delete();
    } catch (e) {
      throw ProfileServiceException('Failed to delete profile: $e');
    }
  }

  /// Streams profile changes in real-time.
  Stream<ProfileModel?> profileStream(String userId) {
    return _profilesRef.doc(userId).snapshots().map((doc) {
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
      Query<Map<String, dynamic>> query = _profilesRef
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
      final doc = await _profilesRef.doc(userId).get();
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
