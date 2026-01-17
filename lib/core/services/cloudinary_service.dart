import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Service for uploading images to Cloudinary.
///
/// Setup Instructions:
/// 1. Create a Cloudinary account at https://cloudinary.com
/// 2. Get your Cloud Name from the dashboard
/// 3. Enable unsigned uploads in Cloudinary dashboard:
///    - Go to: Settings → Upload → Upload Presets
///    - Click "Add upload preset" or edit existing one
///    - Set Preset name: "radius" (or update the constant below)
///    - Change "Signing Mode" to "Unsigned"
///    - Configure allowed formats (jpg, png, etc.)
///    - Set folder restrictions if needed
///    - Save the preset
/// 4. Verify the cloud name and upload preset name match below
///
/// Common Issues:
/// - "Upload preset must be specified": Ensure preset is set to "Unsigned"
/// - "Invalid upload preset": Check preset name spelling matches exactly
/// - Upload fails: Verify cloud name is correct
class CloudinaryService {
  // Cloudinary configuration for unsigned uploads
  // These values are safe to expose in client-side code
  static const String cloudName = 'dloerjd9h';
  static const String uploadPreset = 'radius';

  // Note: Using unsigned uploads for security.
  // Configure upload restrictions in your Cloudinary dashboard:
  // - File size limits
  // - Allowed formats
  // - Upload frequency limits

  /// Uploads an image file to Cloudinary.
  ///
  /// Returns the secure URL of the uploaded image.
  /// Throws an exception if upload fails.
  Future<String> uploadImage(
    File imageFile, {
    String? folder,
    Map<String, dynamic>? tags,
  }) async {
    try {
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      final request = http.MultipartRequest('POST', url);

      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      // Add upload preset for unsigned upload
      request.fields['upload_preset'] = uploadPreset;

      // Optional: Add folder
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      // Optional: Add tags
      if (tags != null && tags.isNotEmpty) {
        request.fields['tags'] = tags.values.join(',');
      }

      // Note: Transformations are better configured in the upload preset
      // on Cloudinary dashboard rather than passed in unsigned uploads
      // to avoid validation errors and security issues

      // Send the request
      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(responseData);
        return data['secure_url'] as String;
      } else {
        // Parse error response for better error messages
        String errorMessage =
            'Upload failed with status: ${response.statusCode}';
        try {
          final errorData = json.decode(responseData);
          if (errorData['error'] != null) {
            final error = errorData['error'];
            if (error['message'] != null) {
              errorMessage = error['message'];
            }
          }
        } catch (_) {
          // If parsing fails, use the raw response
          errorMessage = responseData;
        }

        throw CloudinaryException(
          'Upload failed with status: ${response.statusCode}',
          errorMessage,
        );
      }
    } on CloudinaryException {
      rethrow; // Pass through CloudinaryException as-is
    } catch (e) {
      throw CloudinaryException('Failed to upload image', e.toString());
    }
  }

  /// Extracts the public ID from a Cloudinary URL.
  static String getPublicIdFromUrl(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;

    // Find the upload segment
    final uploadIndex = pathSegments.indexOf('upload');
    if (uploadIndex == -1 || uploadIndex >= pathSegments.length - 1) {
      throw CloudinaryException(
        'Invalid Cloudinary URL',
        'Could not extract public ID from URL',
      );
    }

    // Get everything after 'upload' and the version (if present)
    final publicIdParts = pathSegments.sublist(uploadIndex + 1);

    // Skip version if present (starts with 'v')
    if (publicIdParts.first.startsWith('v') &&
        publicIdParts.first.length > 1 &&
        int.tryParse(publicIdParts.first.substring(1)) != null) {
      publicIdParts.removeAt(0);
    }

    // Join remaining parts and remove file extension
    final publicId = publicIdParts.join('/');
    return publicId.split('.').first;
  }
}

/// Exception thrown when Cloudinary operations fail.
class CloudinaryException implements Exception {
  final String message;
  final String details;

  CloudinaryException(this.message, this.details);

  @override
  String toString() => 'CloudinaryException: $message\nDetails: $details';
}
