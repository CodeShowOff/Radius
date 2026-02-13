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
  final String? discoveryUsername;
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
    this.discoveryUsername,
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
      discoveryUsername: data['discoveryUsername'] as String?,
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
      discoveryUsername: profile.discoveryUsername,
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
      'displayName': _sanitizeField(name, maxNameLength),
      'bio': _sanitizeField(bio, maxBioLength),
      'photoUrl': photoUrl,
      'isVisible': isVisible,
      'isDiscoverable': isVisible, // Keep both for compatibility
      'showOnlineStatus': showOnlineStatus,
      'allowConnectionRequests': allowConnectionRequests,
      'showLastSeen': showLastSeen,
      'vibe': vibe != null ? _sanitizeField(vibe!, maxVibeLength) : null,
      'mood': mood != null ? _sanitizeField(mood!, maxMoodLength) : null,
      'gender': gender != null ? _sanitizeField(gender!, maxGenderLength) : null,
      'discoveryUsername': discoveryUsername,
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
      discoveryUsername: discoveryUsername,
      createdAt: createdAt,
      updatedAt: updatedAt,
      notifyDirectMessages: notifyDirectMessages,
      notifyLocationGroups: notifyLocationGroups,
      notifyNearbyGroups: notifyNearbyGroups,
      notifyRandomGroups: notifyRandomGroups,
    );
  }

  /// Maximum allowed lengths for profile fields.
  static const int maxNameLength = 50;
  static const int maxBioLength = 200;
  static const int maxVibeLength = 50;
  static const int maxMoodLength = 50;
  static const int maxGenderLength = 30;

  /// Sanitizes a profile string field: removes control characters/null bytes,
  /// trims whitespace, and enforces a max length.
  static String _sanitizeField(String value, int maxLength) {
    // Remove null bytes and control characters (except newlines and tabs)
    var sanitized =
        value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    sanitized = sanitized.trim();
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }
    return sanitized;
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
    String? discoveryUsername,
    bool? notifyDirectMessages,
    bool? notifyLocationGroups,
    bool? notifyNearbyGroups,
    bool? notifyRandomGroups,
  }) {
    final map = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) map['displayName'] = _sanitizeField(name, maxNameLength);
    if (bio != null) map['bio'] = _sanitizeField(bio, maxBioLength);
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
    if (vibe != null) map['vibe'] = _sanitizeField(vibe, maxVibeLength);
    if (mood != null) map['mood'] = _sanitizeField(mood, maxMoodLength);
    if (gender != null) map['gender'] = _sanitizeField(gender, maxGenderLength);
    if (discoveryUsername != null) map['discoveryUsername'] = discoveryUsername;

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