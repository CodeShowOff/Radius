import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Service for uploading images to Cloudinary.
///
/// Setup Instructions:
/// 1. Create a Cloudinary account at https://cloudinary.com
/// 2. Get your Cloud Name, API Key, and API Secret from the dashboard
/// 3. Create a .env file or use environment variables:
///    - CLOUDINARY_CLOUD_NAME=your_cloud_name
///    - CLOUDINARY_API_KEY=your_api_key
///    - CLOUDINARY_API_SECRET=your_api_secret
/// 4. Enable unsigned uploads in Cloudinary dashboard:
///    Settings → Upload → Upload presets → Create unsigned preset
/// 5. Set the upload preset name below
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

      // Optional: Add transformation for optimization
      request.fields['transformation'] = json.encode([
        {
          'width': 800,
          'height': 800,
          'crop': 'limit',
          'quality': 'auto:good',
          'fetch_format': 'auto',
        }
      ]);

      // Send the request
      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(responseData);
        return data['secure_url'] as String;
      } else {
        throw CloudinaryException(
          'Upload failed with status: ${response.statusCode}',
          responseData,
        );
      }
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
