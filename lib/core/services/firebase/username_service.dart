import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

/// Service for generating unique usernames using Firestore transactions.
///
/// Usernames are exactly 7 bytes, Base62 encoded (a-z, A-Z, 0-9).
/// Firestore guarantees uniqueness via atomic counter increment.
class UsernameService {
  final FirebaseFirestore _firestore;
  final Logger _logger = Logger();

  static const String _counterCollection = 'counters';
  static const String _counterDocument = 'usernames';
  static const String _counterField = 'value';

  /// Collection for username-to-userId lookups
  static const String _usernameIndexCollection = 'username_index';

  /// Base62 alphabet for encoding
  static const String _base62Alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  UsernameService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Generates a unique username using Firestore transaction.
  ///
  /// Returns a 7-character Base62 username (a-z, A-Z, 0-9).
  /// Throws if the transaction fails.
  Future<String> generateUsername() async {
    final counterRef =
        _firestore.collection(_counterCollection).doc(_counterDocument);

    try {
      // Use Firestore transaction to atomically increment counter
      final username =
          await _firestore.runTransaction<String>((transaction) async {
        // Get current counter value
        final snapshot = await transaction.get(counterRef);

        int counterValue;
        if (!snapshot.exists) {
          // Initialize counter if it doesn't exist
          counterValue = 1;
        } else {
          counterValue = (snapshot.data()?[_counterField] as int? ?? 0) + 1;
        }

        // Update counter
        transaction.set(
          counterRef,
          {_counterField: counterValue},
          SetOptions(merge: true),
        );

        // Encode counter as 7-character Base62 username
        return _encodeBase62(counterValue);
      });

      return username;
    } catch (e) {
      throw Exception('Failed to generate username: $e');
    }
  }

  /// Encodes a number as a 7-character Base62 string.
  ///
  /// Pads with leading zeros if necessary.
  String _encodeBase62(int value) {
    if (value == 0) {
      return '0000000';
    }

    String result = '';
    int num = value;

    while (num > 0) {
      final remainder = num % 62;
      result = _base62Alphabet[remainder] + result;
      num = num ~/ 62;
    }

    // Pad to exactly 7 characters
    while (result.length < 7) {
      result = '0$result';
    }

    // Truncate if longer than 7 characters (shouldn't happen with reasonable usage)
    if (result.length > 7) {
      result = result.substring(result.length - 7);
    }

    return result;
  }

  /// Validates that a username meets requirements:
  /// - Exactly 7 bytes
  /// - ASCII only (a-z, A-Z, 0-9)
  bool isValidUsername(String username) {
    if (username.length != 7) return false;

    // Check that all characters are in Base62 alphabet
    for (int i = 0; i < username.length; i++) {
      if (!_base62Alphabet.contains(username[i])) {
        return false;
      }
    }

    return true;
  }

  /// Stores username in user profile document and creates index entry.
  Future<void> storeUsernameForUser(String userId, String username) async {
    final batch = _firestore.batch();

    // Store username in user document
    batch.set(
      _firestore.collection('users').doc(userId),
      {'username': username},
      SetOptions(merge: true),
    );

    // Create username-to-userId index entry
    batch.set(
      _firestore.collection(_usernameIndexCollection).doc(username),
      {'userId': userId},
    );

    await batch.commit();
  }

  /// Retrieves username for a user.
  Future<String?> getUsernameForUser(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return doc.data()?['username'] as String?;
  }

  /// Looks up userId by username.
  Future<String?> getUserIdByUsername(String username) async {
    final doc = await _firestore
        .collection(_usernameIndexCollection)
        .doc(username)
        .get();
    return doc.data()?['userId'] as String?;
  }

  /// Looks up user profile by username.
  /// Returns null if user not found.
  /// Reads from 'profiles' collection (publicly readable for authenticated users)
  Future<Map<String, dynamic>?> lookupUserByUsername(String username) async {
    try {
      // First get the userId from the index
      final userId = await getUserIdByUsername(username);
      if (userId == null) {
        _logger.d('No userId found for username: $username');
        return null;
      }

      // Fetch from profiles collection (publicly readable)
      final profileDoc =
          await _firestore.collection('profiles').doc(userId).get();
      if (!profileDoc.exists) {
        _logger.d('Profile document does not exist for userId: $userId');
        return null;
      }

      final profile = profileDoc.data();
      if (profile == null) {
        _logger.d('Profile data is null for userId: $userId');
        return null;
      }

      final result = {
        'userId': userId,
        'username': username,
        'displayName': (profile['displayName'] as String?)?.trim().isNotEmpty == true
            ? (profile['displayName'] as String)
            : 'User $username',
        'photoUrl': profile['photoUrl'],
        'bio': profile['bio'],
        'vibe': profile['vibe'],
        'mood': profile['mood'],
        'gender': profile['gender'],
      };

      _logger.d(
          'Successfully looked up profile for $username: displayName=${result['displayName']}, photoUrl=${result['photoUrl']}');

      return result;
    } catch (e, stack) {
      _logger.e('Error looking up profile for $username',
          error: e, stackTrace: stack);
      return null;
    }
  }
}
