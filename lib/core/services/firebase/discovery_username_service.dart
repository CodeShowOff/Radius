import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

/// Service for managing discovery usernames - unique, user-chosen usernames
/// (like Instagram handles) that allow users to find each other online.
///
/// This is separate from the auto-generated BLE username used for proximity.
///
/// Firestore Collections:
/// - `discovery_usernames` - Username-to-userId index (ensures uniqueness)
/// - `users/{userId}` - Stores `discoveryUsername` field on user doc
/// - `profiles/{userId}` - Also stores `discoveryUsername` for public lookups
class DiscoveryUsernameService {
  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  /// Collection for discovery username-to-userId lookups.
  static const String _indexCollection = 'discovery_usernames';

  /// Minimum username length.
  static const int minLength = 3;

  /// Maximum username length.
  static const int maxLength = 30;

  /// Regex for valid characters: lowercase letters, numbers, underscores, periods.
  static final RegExp _validPattern = RegExp(r'^[a-z0-9._]+$');

  /// Disallowed patterns/reserved words.
  static const List<String> _reservedWords = [
    'admin',
    'radius',
    'support',
    'help',
    'system',
    'null',
    'undefined',
    'official',
    'moderator',
    'mod',
  ];

  DiscoveryUsernameService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Validates a discovery username format (client-side only, no Firestore call).
  ///
  /// Returns null if valid, or an error message string.
  String? validateFormat(String username) {
    if (username.isEmpty) {
      return 'Username cannot be empty';
    }
    if (username.length < minLength) {
      return 'Username must be at least $minLength characters';
    }
    if (username.length > maxLength) {
      return 'Username must be at most $maxLength characters';
    }
    if (!_validPattern.hasMatch(username)) {
      return 'Only lowercase letters, numbers, underscores, and periods allowed';
    }
    if (username.startsWith('.') || username.startsWith('_')) {
      return 'Username cannot start with a period or underscore';
    }
    if (username.endsWith('.') || username.endsWith('_')) {
      return 'Username cannot end with a period or underscore';
    }
    if (username.contains('..') || username.contains('__')) {
      return 'Username cannot contain consecutive periods or underscores';
    }
    final lower = username.toLowerCase();
    for (final word in _reservedWords) {
      if (lower == word) {
        return 'This username is reserved';
      }
    }
    return null;
  }

  /// Checks if a discovery username is available (not taken by another user).
  ///
  /// [excludeUserId] - if provided, the current user's own username won't
  /// count as "taken" (useful when user is re-checking their own username).
  Future<bool> isUsernameAvailable(
    String username, {
    String? excludeUserId,
  }) async {
    try {
      final normalized = username.toLowerCase().trim();
      final doc = await _firestore
          .collection(_indexCollection)
          .doc(normalized)
          .get();

      if (!doc.exists) return true;

      // If the username belongs to the current user, it's "available" for them
      if (excludeUserId != null) {
        final existingUserId = doc.data()?['userId'] as String?;
        if (existingUserId == excludeUserId) return true;
      }

      return false;
    } catch (e) {
      _logger.e('Error checking username availability', error: e);
      return false;
    }
  }

  /// Claims a discovery username for a user. Handles:
  /// - Releasing old username if user had one
  /// - Creating new index entry
  /// - Updating user and profile documents
  ///
  /// Returns true on success, false on failure (e.g., race condition / already taken).
  Future<bool> claimUsername({
    required String userId,
    required String newUsername,
    String? oldUsername,
  }) async {
    final normalized = newUsername.toLowerCase().trim();

    try {
      // Use a transaction to atomically check + claim
      return await _firestore.runTransaction<bool>((transaction) async {
        // Check if the new username is already taken
        final indexRef =
            _firestore.collection(_indexCollection).doc(normalized);
        final indexDoc = await transaction.get(indexRef);

        if (indexDoc.exists) {
          final existingUserId = indexDoc.data()?['userId'] as String?;
          if (existingUserId != null && existingUserId != userId) {
            // Already taken by another user
            return false;
          }
        }

        // Release old username if different
        if (oldUsername != null &&
            oldUsername.isNotEmpty &&
            oldUsername.toLowerCase() != normalized) {
          final oldRef = _firestore
              .collection(_indexCollection)
              .doc(oldUsername.toLowerCase());
          transaction.delete(oldRef);
        }

        // Claim the new username in the index
        transaction.set(indexRef, {
          'userId': userId,
          'claimedAt': FieldValue.serverTimestamp(),
        });

        // Update user document
        final userRef = _firestore.collection('users').doc(userId);
        transaction.set(
          userRef,
          {'discoveryUsername': normalized},
          SetOptions(merge: true),
        );

        // Update profiles document
        final profileRef = _firestore.collection('profiles').doc(userId);
        transaction.set(
          profileRef,
          {'discoveryUsername': normalized},
          SetOptions(merge: true),
        );

        return true;
      });
    } catch (e) {
      _logger.e('Error claiming discovery username', error: e);
      return false;
    }
  }

  /// Searches for a user by their exact discovery username.
  ///
  /// Returns user profile data map or null if not found.
  Future<Map<String, dynamic>?> searchByUsername(String username) async {
    try {
      final normalized = username.toLowerCase().trim();
      if (normalized.isEmpty) return null;

      // Look up userId from index
      final indexDoc = await _firestore
          .collection(_indexCollection)
          .doc(normalized)
          .get();

      if (!indexDoc.exists) return null;

      final userId = indexDoc.data()?['userId'] as String?;
      if (userId == null) return null;

      // Fetch profile
      final profileDoc =
          await _firestore.collection('profiles').doc(userId).get();

      if (!profileDoc.exists) return null;

      final data = profileDoc.data();
      if (data == null) return null;

      return {
        'userId': userId,
        'discoveryUsername': normalized,
        'displayName':
            (data['displayName'] as String?)?.trim().isNotEmpty == true
                ? data['displayName'] as String
                : 'User',
        'photoUrl': data['photoUrl'],
        'bio': data['bio'],
        'vibe': data['vibe'],
        'mood': data['mood'],
        'gender': data['gender'],
        'allowConnectionRequests':
            data['allowConnectionRequests'] as bool? ?? true,
      };
    } catch (e) {
      _logger.e('Error searching by discovery username', error: e);
      return null;
    }
  }

  /// Searches for users whose discovery username starts with [prefix].
  ///
  /// Returns up to [limit] results.
  Future<List<Map<String, dynamic>>> searchByPrefix(
    String prefix, {
    int limit = 10,
  }) async {
    try {
      final normalized = prefix.toLowerCase().trim();
      if (normalized.isEmpty) return [];

      // Firestore range query for prefix matching
      final endPrefix = normalized.substring(0, normalized.length - 1) +
          String.fromCharCode(
              normalized.codeUnitAt(normalized.length - 1) + 1);

      final querySnapshot = await _firestore
          .collection(_indexCollection)
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: normalized)
          .where(FieldPath.documentId, isLessThan: endPrefix)
          .limit(limit)
          .get();

      if (querySnapshot.docs.isEmpty) return [];

      final results = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final userId = doc.data()['userId'] as String?;
        if (userId == null) continue;

        final profileDoc =
            await _firestore.collection('profiles').doc(userId).get();

        if (!profileDoc.exists) continue;

        final data = profileDoc.data();
        if (data == null) continue;

        results.add({
          'userId': userId,
          'discoveryUsername': doc.id,
          'displayName':
              (data['displayName'] as String?)?.trim().isNotEmpty == true
                  ? data['displayName'] as String
                  : 'User',
          'photoUrl': data['photoUrl'],
          'bio': data['bio'],
          'vibe': data['vibe'],
        });
      }

      return results;
    } catch (e) {
      _logger.e('Error searching by prefix', error: e);
      return [];
    }
  }

  /// Gets the discovery username for a user (if set).
  Future<String?> getDiscoveryUsername(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      return doc.data()?['discoveryUsername'] as String?;
    } catch (e) {
      _logger.e('Error getting discovery username', error: e);
      return null;
    }
  }
}
