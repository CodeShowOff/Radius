import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:injectable/injectable.dart';

import '../../../features/profile/data/models/profile_model.dart';

/// Service for profile-related Firestore operations.
/// Writes to both `users` and `profiles` collections to keep data mirrored.
/// Consistent field names: photoUrl (not avatarUrl), displayName (not name)
@lazySingleton
class ProfileService {
  final FirebaseFirestore _firestore;

  static const String _usersCollection = 'users';
  static const String _profilesCollection = 'profiles';

  ProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Reference to users collection - the single source of truth.
  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection(_usersCollection);

  /// Reference to profiles collection (denormalized public profile view).
  CollectionReference<Map<String, dynamic>> get _profilesRef =>
      _firestore.collection(_profilesCollection);

  /// Writes the same data to both users and profiles documents.
  /// If [isCreate] is true, creates only the profiles doc (users doc is created by auth flow).
  /// Otherwise uses merge for updates on both collections.
  /// Always includes userId in the data to satisfy Firestore create rules for profiles collection.
  Future<void> _writeToUserAndProfile(
    String userId,
    Map<String, dynamic> data, {
    bool isCreate = false,
  }) async {
    final batch = _firestore.batch();
    final userDoc = _usersRef.doc(userId);
    final profileDoc = _profilesRef.doc(userId);

    // Always include userId in data - required by profiles collection create rule
    // This ensures that even merge operations on non-existent profiles docs succeed
    final dataWithUserId = {
      ...data,
      'userId': userId,
    };

    // For users collection, exclude immutable fields (createdAt, email) to avoid security rule violations  
    // These fields are already set during user creation and cannot be changed per security rules
    final dataForUsers = Map<String, dynamic>.from(dataWithUserId)
      ..remove('createdAt')
      ..remove('email');

    if (isCreate) {
      // For initial profile creation:
      // - The users doc is already created by auth flow with required fields (email, createdAt)
      // - Only update users doc with merge to add profile fields without overwriting auth fields
      // - Create profiles doc fresh (it doesn't exist yet)
      //
      // IMPORTANT: Remove discoveryUsername from initial creation data.
      // The cloud function (onUserCreatedAssignDiscoveryUsername) auto-assigns
      // this field asynchronously. Including null here would overwrite the
      // cloud function's value due to a race condition (merge with null
      // sets the field to null in Firestore).
      final createDataForUsers = Map<String, dynamic>.from(dataForUsers)
        ..remove('discoveryUsername');
      final createDataForProfile = Map<String, dynamic>.from(dataWithUserId)
        ..remove('discoveryUsername');

      batch.set(userDoc, createDataForUsers, SetOptions(merge: true));
      batch.set(profileDoc, createDataForProfile);
    } else {
      // Use merge for updates to preserve existing fields
      // Include userId in case profiles doc doesn't exist yet (migration scenario)
      batch.set(userDoc, dataForUsers, SetOptions(merge: true));
      batch.set(profileDoc, dataWithUserId, SetOptions(merge: true));
    }

    await batch.commit();
  }

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
  /// Includes retry logic to handle race conditions during authentication.
  /// This method is resilient to permission-denied errors that can occur when
  /// the auth token hasn't fully propagated to Firestore yet.
  Future<void> createProfile(ProfileModel profile) async {
    const maxRetries = 4;
    const initialDelay = Duration(milliseconds: 300);
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final profileData = profile.toFirestore();

        // Use isCreate=true to trigger 'create' rule instead of 'update' rule
        await _writeToUserAndProfile(profile.userId, profileData, isCreate: true);
        return; // Success - exit the retry loop
      } catch (e) {
        final errorString = e.toString().toLowerCase();
        final isPermissionError = errorString.contains('permission-denied') || 
                                  errorString.contains('permission_denied') ||
                                  errorString.contains('permission denied');
        final isLastAttempt = attempt == maxRetries - 1;
        
        if (isPermissionError && !isLastAttempt) {
          // Wait before retrying with exponential backoff
          final delay = initialDelay * (attempt + 1);
          await Future.delayed(delay);
          continue; // Retry
        }
        
        // If not a permission error or last attempt failed, throw
        throw ProfileServiceException('Failed to create profile: $e');
      }
    }
  }

  /// Creates a new profile without retry logic.
  /// Use this when the caller already has retry logic to avoid nested retries.
  Future<void> createProfileDirect(ProfileModel profile) async {
    try {
      final profileData = profile.toFirestore();
      await _writeToUserAndProfile(profile.userId, profileData, isCreate: true);
    } catch (e) {
      throw ProfileServiceException('Failed to create profile: $e');
    }
  }

  /// Updates an existing profile.
  Future<void> updateProfile(String userId, Map<String, dynamic> data) async {
    try {
      await _writeToUserAndProfile(userId, data);
    } catch (e) {
      throw ProfileServiceException('Failed to update profile: $e');
    }
  }

  /// Updates profile photo URL.
  Future<void> updateProfilePhoto(String userId, String photoUrl) async {
    try {
      await _writeToUserAndProfile(userId, {
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
      await _writeToUserAndProfile(userId, {
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
      final batch = _firestore.batch();
      batch.delete(_usersRef.doc(userId));
      batch.delete(_profilesRef.doc(userId));
      await batch.commit();
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
      // Note: We can't use .where('isVisible', isEqualTo: true) because
      // Firestore queries don't support default values. Documents without
      // the isVisible field won't match even though our Dart code defaults it to true.
      // So we fetch all profiles and filter in Dart code.
      Query<Map<String, dynamic>> query = _usersRef
          .orderBy('updatedAt', descending: true);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      
      // Filter by visibility in Dart where we can apply default values
      final visibleProfiles = snapshot.docs
          .where((doc) {
            final data = doc.data();
            // Default to true if field doesn't exist
            final isVisible = data['isVisible'] as bool? ?? true;
            return isVisible;
          })
          .take(limit)
          .map((doc) => ProfileModel.fromFirestore(doc))
          .toList();
      
      return visibleProfiles;
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
