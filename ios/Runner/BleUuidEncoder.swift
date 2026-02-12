import Foundation

/**
 * Encodes/decodes usernames into BLE Service UUIDs for iOS background advertising.
 *
 * iOS strips Service Data in background, but preserves Service UUIDs.
 * We encode the 7-character username into the UUID itself.
 *
 * UUID Structure:
 * ```
 * 0000BEEF-UUUU-UUUU-8000-XXXXXXXXXXXX
 *          ^^^^-^^^^
 *          Username encoded here (56 bits)
 * ```
 *
 * Base62 encoding (a-z=0-25, A-Z=26-51, 0-9=52-61)
 * 7 chars × 62 values = 62^7 = 3,521,614,606,208 combinations
 * Requires 42 bits (we use 64 bits for cleaner encoding)
 */
class BleUuidEncoder {
    
    // Base62 character set
    private static let base62Chars = 
        "abcdefghijklmnopqrstuvwxyz" +
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
        "0123456789"
    
    private static let usernameLength = 7
    
    /// Encodes a 7-character username into a 128-bit UUID string.
    ///
    /// Returns format: "0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX"
    /// where XXXX encodes the username.
    static func encodeUsernameToUuid(_ username: String) -> String? {
        guard username.count == usernameLength else { return nil }
        
        // Encode username to a 64-bit integer
        var encoded: UInt64 = 0
        for char in username {
            guard let index = base62Chars.firstIndex(of: char) else { return nil }
            let value = base62Chars.distance(from: base62Chars.startIndex, to: index)
            encoded = encoded * 62 + UInt64(value)
        }
        
        // Split 64-bit encoded value into parts
        let part2 = (encoded >> 48) & 0xFFFF     // Upper 16 bits
        let part3 = (encoded >> 32) & 0xFFFF     // Next 16 bits
        let part5high = (encoded >> 16) & 0xFFFF // Next 16 bits
        let part5mid = (encoded >> 8) & 0xFF     // Next 8 bits
        let part5low = encoded & 0xFF            // Lower 8 bits
        
        // Format: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX
        //         section1 sect2 sect3 sect4 section5(12 hex = 48 bits)
        let uuid = String(format: "0000BEEF-%04X-%04X-8000-%04X%02X%02X0000",
                         part2, part3, part5high, part5mid, part5low)
        
        return uuid
    }
    
    /// Decodes a UUID string back to the 7-character username.
    ///
    /// Returns nil if the UUID doesn't match the Radius encoding pattern.
    static func decodeUuidToUsername(_ uuid: String) -> String? {
        // Normalize UUID (remove dashes and convert to uppercase)
        let normalized = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        
        // Check if it's a Radius UUID (starts with 0000BEEF)
        guard normalized.hasPrefix("0000BEEF") else { return nil }
        guard normalized.count == 32 else { return nil }
        
        // Extract encoded parts
        // Format: 0000BEEF-XXXX-XXXX-8000-XXXXXXXXXXXX
        //         01234567 8901 2345 6789 012345678901234 (hex positions)
        let index8 = normalized.index(normalized.startIndex, offsetBy: 8)
        let index12 = normalized.index(normalized.startIndex, offsetBy: 12)
        let index16 = normalized.index(normalized.startIndex, offsetBy: 16)
        let index20 = normalized.index(normalized.startIndex, offsetBy: 20)
        let index24 = normalized.index(normalized.startIndex, offsetBy: 24)
        let index26 = normalized.index(normalized.startIndex, offsetBy: 26)
        let index28 = normalized.index(normalized.startIndex, offsetBy: 28)
        
        guard let part2 = UInt64(normalized[index8..<index12], radix: 16),
              let part3 = UInt64(normalized[index12..<index16], radix: 16),
              let part5high = UInt64(normalized[index20..<index24], radix: 16),
              let part5mid = UInt64(normalized[index24..<index26], radix: 16),
              let part5low = UInt64(normalized[index26..<index28], radix: 16) else {
            return nil
        }
        
        // Reconstruct the 64-bit encoded value
        let encoded = (part2 << 48) | (part3 << 32) | (part5high << 16) | (part5mid << 8) | part5low
        
        // Decode from base62
        return decodeBase62(encoded)
    }
    
    /// Checks if a UUID is a Radius-encoded UUID.
    static func isRadiusUuid(_ uuid: String) -> Bool {
        let normalized = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        return normalized.hasPrefix("0000BEEF")
    }
    
    // Helper: Decode base62 integer to username string
    private static func decodeBase62(_ encoded: UInt64) -> String? {
        var chars: [Character] = []
        var remaining = encoded
        
        // Decode 7 characters
        for _ in 0..<usernameLength {
            let index = Int(remaining % 62)
            let charIndex = base62Chars.index(base62Chars.startIndex, offsetBy: index)
            chars.insert(base62Chars[charIndex], at: 0)
            remaining /= 62
        }
        
        let result = String(chars)
        
        // Validate result
        guard result.count == usernameLength else { return nil }
        
        return result
    }
    
    /// Validates that a username can be encoded.
    static func isValidUsername(_ username: String) -> Bool {
        guard username.count == usernameLength else { return false }
        return username.allSatisfy { base62Chars.contains($0) }
    }
}
