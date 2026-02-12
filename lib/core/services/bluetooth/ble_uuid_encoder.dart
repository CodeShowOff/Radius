import 'ble_constants.dart';

/// Encodes/decodes usernames into BLE Service UUIDs for iOS background advertising.
///
/// iOS strips Service Data in background, but preserves Service UUIDs.
/// We encode the 7-character username into the UUID itself.
///
/// UUID Structure:
/// ```
/// 0000BEEF-UUUU-UUUU-8000-XXXXXXXXXXXX
///          ^^^^-^^^^
///          Username encoded here (56 bits)
/// ```
///
/// Base62 encoding (a-z=0-25, A-Z=26-51, 0-9=52-61)
/// 7 chars × 62 values = 62^7 = 3,521,614,606,208 combinations
/// Requires 42 bits (we use 56 bits for cleaner hex encoding)
class BleUuidEncoder {
  // Base62 character set
  static const String _base62Chars = 
      'abcdefghijklmnopqrstuvwxyz'
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      '0123456789';

  /// Encodes a 7-character username into a 128-bit UUID string.
  ///
  /// Returns format: "0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX"
  /// where XXXX encodes the username.
  static String encodeUsernameToUuid(String username) {
    if (username.length != BleConstants.usernameLength) {
      throw ArgumentError('Username must be exactly ${BleConstants.usernameLength} characters');
    }

    // Encode username to a 64-bit integer
    int encoded = 0;
    for (int i = 0; i < username.length; i++) {
      final char = username[i];
      final index = _base62Chars.indexOf(char);
      if (index == -1) {
        throw ArgumentError('Username must contain only a-z, A-Z, 0-9');
      }
      encoded = encoded * 62 + index;
    }

    // Format as UUID: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX
    // We put the encoded value in sections 2, 3, and 5
    // 128 bits total: 32 (section 1) + 16 (section 2) + 16 (section 3) + 16 (section 4) + 48 (section 5)
    
    // Split 64-bit encoded value into parts
    final part2 = (encoded >> 48) & 0xFFFF; // Upper 16 bits
    final part3 = (encoded >> 32) & 0xFFFF; // Next 16 bits
    final part5high = (encoded >> 16) & 0xFFFF; // Next 16 bits 
    final part5mid = (encoded >> 8) & 0xFF;     // Next 8 bits
    final part5low = encoded & 0xFF;             // Lower 8 bits

    // Format: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX
    //         section1 sect2 sect3 sect4 section5(12 hex = 48 bits)
    final uuid = '0000BEEF-'
        '${_toHex4(part2)}-'
        '${_toHex4(part3)}-'
        '8000-'
        '${_toHex4(part5high)}${_toHex2(part5mid)}${_toHex2(part5low)}0000';  // Pad to 12 hex digits

    return uuid.toUpperCase();
  }

  /// Decodes a UUID string back to the 7-character username.
  ///
  /// Returns null if the UUID doesn't match the Radius encoding pattern.
  static String? decodeUuidToUsername(String uuid) {
    try {
      // Normalize UUID (remove dashes and convert to uppercase)
      final normalized = uuid.replaceAll('-', '').toUpperCase();

      // Check if it's a Radius UUID (starts with 0000BEEF)
      if (!normalized.startsWith('0000BEEF')) {
        return null;
      }

      // Extract encoded parts
      // Format: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX
      //         01234567 8901 2345 6789 012345678901234 (hex positions)
      //                  ^^^^ ^^^^ ^^^^ ^^^^^^^^^^^^
      
      final part2 = int.parse(normalized.substring(8, 12), radix: 16);
      final part3 = int.parse(normalized.substring(12, 16), radix: 16);
      // Skip section 4 (variant/version bits: 8000)
      final part5high = int.parse(normalized.substring(20, 24), radix: 16);
      final part5mid = int.parse(normalized.substring(24, 26), radix: 16);
      final part5low = int.parse(normalized.substring(26, 28), radix: 16);
      // Last 2 bytes (28-32) are padding (00)

      // Reconstruct the 64-bit encoded value (only 40 bits are used, upper 24 bits are 0)
      final encoded = (part2 << 48) | (part3 << 32) | (part5high << 16) | (part5mid << 8) | part5low;

      // Decode from base62
      return _decodeBase62(encoded);
    } catch (e) {
      return null;
    }
  }

  /// Checks if a UUID is a Radius-encoded UUID.
  static bool isRadiusUuid(String uuid) {
    final normalized = uuid.replaceAll('-', '').toUpperCase();
    return normalized.startsWith('0000BEEF');
  }

  // Helper: Convert int to 4-digit hex string
  static String _toHex4(int value) {
    return value.toRadixString(16).padLeft(4, '0');
  }

  // Helper: Convert int to 2-digit hex string
  static String _toHex2(int value) {
    return value.toRadixString(16).padLeft(2, '0');
  }

  // Helper: Decode base62 integer to username string
  static String _decodeBase62(int encoded) {
    if (encoded < 0) return '';

    final chars = <String>[];
    var remaining = encoded;

    // Decode 7 characters
    for (int i = 0; i < BleConstants.usernameLength; i++) {
      chars.insert(0, _base62Chars[remaining % 62]);
      remaining ~/= 62;
    }

    final result = chars.join();
    
    // Validate result
    if (result.length != BleConstants.usernameLength) {
      throw ArgumentError('Decoded username has invalid length');
    }

    return result;
  }

  /// Validates that a username can be encoded.
  static bool isValidUsername(String username) {
    if (username.length != BleConstants.usernameLength) {
      return false;
    }
    return RegExp(r'^[a-zA-Z0-9]{7}$').hasMatch(username);
  }
}
