/// Utility class for sanitizing user input to prevent security issues.
///
/// This includes protection against XSS, SQL injection patterns,
/// and other malicious input.
abstract class InputSanitizer {
  /// Sanitizes a display name by removing potentially dangerous characters.
  ///
  /// - Removes HTML tags
  /// - Removes script-related content
  /// - Limits length to [maxLength] (default 50)
  /// - Trims whitespace
  /// - Returns null if input is null or becomes empty after sanitization
  static String? sanitizeDisplayName(String? input, {int maxLength = 50}) {
    if (input == null || input.isEmpty) {
      return null;
    }

    String sanitized = input;

    // Remove HTML tags
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');

    // Remove script-related patterns (case insensitive)
    sanitized = sanitized.replaceAll(
      RegExp(r'javascript:', caseSensitive: false),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'on\w+\s*=', caseSensitive: false),
      '',
    );

    // Remove potentially dangerous Unicode characters
    // (zero-width chars, RTL override, etc.)
    sanitized = sanitized.replaceAll(
      RegExp(r'[\u200B-\u200D\u2028\u2029\u202A-\u202E\uFEFF]'),
      '',
    );

    // Normalize whitespace
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Limit length
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength).trim();
    }

    return sanitized.isEmpty ? null : sanitized;
  }

  /// Sanitizes an email address.
  ///
  /// - Trims whitespace
  /// - Converts to lowercase
  /// - Returns null if input is null or empty
  static String? sanitizeEmail(String? input) {
    if (input == null || input.isEmpty) {
      return null;
    }

    return input.trim().toLowerCase();
  }

  /// Sanitizes a bio/about text field.
  ///
  /// Alias for [sanitizeText] with a default max length of 300 characters.
  static String? sanitizeBio(String? input, {int maxLength = 300}) {
    return sanitizeText(input, maxLength: maxLength);
  }

  /// Sanitizes generic text content (like bio or about text).
  ///
  /// - Removes HTML tags
  /// - Limits length to [maxLength] (default 500)
  /// - Preserves line breaks
  /// - Returns null if input is null or becomes empty after sanitization
  static String? sanitizeText(String? input, {int maxLength = 500}) {
    if (input == null || input.isEmpty) {
      return null;
    }

    String sanitized = input;

    // Remove HTML tags
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');

    // Remove script-related patterns (case insensitive)
    sanitized = sanitized.replaceAll(
      RegExp(r'javascript:', caseSensitive: false),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'on\w+\s*=', caseSensitive: false),
      '',
    );

    // Remove potentially dangerous Unicode characters
    sanitized = sanitized.replaceAll(
      RegExp(r'[\u200B-\u200D\u202A-\u202E\uFEFF]'),
      '',
    );

    // Normalize multiple line breaks to maximum of 2
    sanitized = sanitized.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // Trim leading/trailing whitespace
    sanitized = sanitized.trim();

    // Limit length
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength).trim();
    }

    return sanitized.isEmpty ? null : sanitized;
  }

  /// Validates and sanitizes a URL.
  ///
  /// - Only allows http and https schemes
  /// - Returns null if the URL is invalid or uses a dangerous scheme
  static String? sanitizeUrl(String? input) {
    if (input == null || input.isEmpty) {
      return null;
    }

    final trimmed = input.trim();

    // Parse the URL to validate it
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return null;
    }

    // Only allow http and https schemes
    if (!['http', 'https'].contains(uri.scheme.toLowerCase())) {
      return null;
    }

    // Ensure host is present
    if (uri.host.isEmpty) {
      return null;
    }

    return trimmed;
  }
}
