import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/profile.dart';

/// Data Transfer Object for Profile entity.
/// Handles Firestore serialization/deserialization.
class ProfileModel {
  final String id;
  final String userId;
  final String name;
  final String bio;
  final String? photoUrl;
  final bool isVisible;
  final bool showOnlineStatus;
  final bool allowConnectionRequests;
  final bool showLastSeen;
  final String? vibe;
  final String? mood;
  final String? gender;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool notifyDirectMessages;
  final bool notifyLocationGroups;
  final bool notifyNearbyGroups;
  final bool notifyRandomGroups;

  const ProfileModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.bio,
    this.photoUrl,
    required this.isVisible,
    this.showOnlineStatus = true,
    this.allowConnectionRequests = true,
    this.showLastSeen = true,
    this.vibe,
    this.mood,
    this.gender,
    required this.createdAt,
    required this.updatedAt,
    this.notifyDirectMessages = true,
    this.notifyLocationGroups = true,
    this.notifyNearbyGroups = true,
    this.notifyRandomGroups = true,
  });

  /// Creates ProfileModel from Firestore document.
  /// Reads from users collection which uses 'displayName' and 'photoUrl'
  factory ProfileModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final notifPrefs = data['notificationPreferences'] as Map<String, dynamic>?;
    return ProfileModel(
      id: doc.id,
      userId: data['userId'] as String? ?? doc.id,
      // Read from 'displayName' (users collection) or fallback to 'name' (legacy)
      name: data['displayName'] as String? ?? data['name'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      isVisible: data['isVisible'] as bool? ?? true,
      showOnlineStatus: data['showOnlineStatus'] as bool? ?? true,
      allowConnectionRequests: data['allowConnectionRequests'] as bool? ?? true,
      showLastSeen: data['showLastSeen'] as bool? ?? true,
      vibe: data['vibe'] as String?,
      mood: data['mood'] as String?,
      gender: data['gender'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notifyDirectMessages: notifPrefs?['directMessages'] as bool? ?? true,
      notifyLocationGroups: notifPrefs?['locationGroups'] as bool? ?? true,
      notifyNearbyGroups: notifPrefs?['nearbyGroups'] as bool? ?? true,
      notifyRandomGroups: notifPrefs?['randomGroups'] as bool? ?? true,
    );
  }

  /// Creates ProfileModel from domain entity.
  factory ProfileModel.fromEntity(Profile profile) {
    return ProfileModel(
      id: profile.id,
      userId: profile.userId,
      name: profile.name,
      bio: profile.bio,
      photoUrl: profile.photoUrl,
      isVisible: profile.isVisible,
      showOnlineStatus: profile.showOnlineStatus,
      allowConnectionRequests: profile.allowConnectionRequests,
      showLastSeen: profile.showLastSeen,
      vibe: profile.vibe,
      mood: profile.mood,
      gender: profile.gender,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
      notifyDirectMessages: profile.notifyDirectMessages,
      notifyLocationGroups: profile.notifyLocationGroups,
      notifyNearbyGroups: profile.notifyNearbyGroups,
      notifyRandomGroups: profile.notifyRandomGroups,
    );
  }

  /// Converts to Firestore document map.
  /// Stores in users collection with 'displayName' (not 'name')
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'displayName': name, // Use displayName for users collection
      'bio': bio,
      'photoUrl': photoUrl,
      'isVisible': isVisible,
      'isDiscoverable': isVisible, // Keep both for compatibility
      'showOnlineStatus': showOnlineStatus,
      'allowConnectionRequests': allowConnectionRequests,
      'showLastSeen': showLastSeen,
      'vibe': vibe,
      'mood': mood,
      'gender': gender,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'notificationPreferences': {
        'directMessages': notifyDirectMessages,
        'locationGroups': notifyLocationGroups,
        'nearbyGroups': notifyNearbyGroups,
        'randomGroups': notifyRandomGroups,
      },
    };
  }

  /// Converts to domain entity.
  Profile toEntity() {
    return Profile(
      id: id,
      userId: userId,
      name: name,
      bio: bio,
      photoUrl: photoUrl,
      isVisible: isVisible,
      showOnlineStatus: showOnlineStatus,
      allowConnectionRequests: allowConnectionRequests,
      showLastSeen: showLastSeen,
      vibe: vibe,
      mood: mood,
      gender: gender,
      createdAt: createdAt,
      updatedAt: updatedAt,
      notifyDirectMessages: notifyDirectMessages,
      notifyLocationGroups: notifyLocationGroups,
      notifyNearbyGroups: notifyNearbyGroups,
      notifyRandomGroups: notifyRandomGroups,
    );
  }

  /// Creates a map for partial updates (only changed fields).
  /// Uses 'displayName' for users collection consistency
  static Map<String, dynamic> toUpdateMap({
    String? name,
    String? bio,
    String? photoUrl,
    bool? isVisible,
    bool? showOnlineStatus,
    bool? allowConnectionRequests,
    bool? showLastSeen,
    String? vibe,
    String? mood,
    String? gender,
    bool? notifyDirectMessages,
    bool? notifyLocationGroups,
    bool? notifyNearbyGroups,
    bool? notifyRandomGroups,
  }) {
    final map = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) map['displayName'] = name; // Use displayName for users collection
    if (bio != null) map['bio'] = bio;
    if (photoUrl != null) map['photoUrl'] = photoUrl;
    if (isVisible != null) {
      map['isVisible'] = isVisible;
      map['isDiscoverable'] = isVisible; // Keep both for compatibility
    }
    if (showOnlineStatus != null) map['showOnlineStatus'] = showOnlineStatus;
    if (allowConnectionRequests != null) {
      map['allowConnectionRequests'] = allowConnectionRequests;
    }
    if (showLastSeen != null) map['showLastSeen'] = showLastSeen;
    if (vibe != null) map['vibe'] = vibe;
    if (mood != null) map['mood'] = mood;
    if (gender != null) map['gender'] = gender;

    // Handle notification preferences as nested map
    if (notifyDirectMessages != null || notifyLocationGroups != null ||
        notifyNearbyGroups != null || notifyRandomGroups != null) {
      final notifPrefs = <String, dynamic>{};
      if (notifyDirectMessages != null) notifPrefs['directMessages'] = notifyDirectMessages;
      if (notifyLocationGroups != null) notifPrefs['locationGroups'] = notifyLocationGroups;
      if (notifyNearbyGroups != null) notifPrefs['nearbyGroups'] = notifyNearbyGroups;
      if (notifyRandomGroups != null) notifPrefs['randomGroups'] = notifyRandomGroups;
      map['notificationPreferences'] = notifPrefs;
    }

    return map;
  }
}
