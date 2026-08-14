import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../../core/error/exceptions.dart';

/// Result of a post media upload operation.
class PostUploadResult {
  final String downloadUrl;
  final String storagePath;
  final int fileSize;

  const PostUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.fileSize,
  });
}

/// Service for uploading and deleting post media files in Firebase Storage.
///
/// Storage paths:
/// - `post_media/images/{authorId}/{postId}/{uuid}.ext` (max 20MB)
/// - `post_media/videos/{authorId}/{postId}/{uuid}.ext` (max 100MB)
/// - `post_media/thumbnails/{authorId}/{postId}/{uuid}.jpg` (max 5MB)
class PostMediaService {
  final Logger _logger;
  static const String _backendUrl = 'http://192.168.13.103:3000/api/upload';

  static const String _imagesPath = 'post_media/images';
  static const String _videosPath = 'post_media/videos';
  static const String _thumbnailsPath = 'post_media/thumbnails';

  static const _uuid = Uuid();

  PostMediaService({
    Logger? logger,
  })  : _logger = logger ?? Logger();

  /// Uploads a post image and returns the download URL + storage path.
  Future<PostUploadResult> uploadImage({
    required File file,
    required String authorId,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _imagesPath,
      authorId: authorId,
      postId: postId,
      onProgress: onProgress,
    );
  }

  /// Uploads a post video and returns the download URL + storage path.
  Future<PostUploadResult> uploadVideo({
    required File file,
    required String authorId,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _videosPath,
      authorId: authorId,
      postId: postId,
      onProgress: onProgress,
    );
  }

  /// Uploads a video thumbnail and returns the download URL + storage path.
  Future<PostUploadResult> uploadThumbnail({
    required File file,
    required String authorId,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _thumbnailsPath,
      authorId: authorId,
      postId: postId,
      onProgress: onProgress,
    );
  }

  /// Generic file upload handler.
  Future<PostUploadResult> _uploadFile({
    required File file,
    required String storagePath,
    required String authorId,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    try {
      if (!await file.exists()) {
        throw const DatabaseException(
          message: 'File does not exist',
          code: 'file-not-found',
        );
      }

      final fileSize = await file.length();
      final fileName = file.path.split(Platform.pathSeparator).last;
      final extension = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';

      _validateFileSize(fileSize, storagePath);
      _validateFileExtension(extension, storagePath);
      await _validateMagicBytes(file, extension);

      final fileId = _uuid.v4();
      final filePath = '$storagePath/$authorId/$postId/$fileId$extension';

      _logger.d('Uploading post media to: $filePath ($fileSize bytes)');

      // HTTP Upload
      if (onProgress != null) onProgress(0.1);
      final request = http.MultipartRequest('POST', Uri.parse(_backendUrl));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      if (response.statusCode != 200) {
         throw DatabaseException(
           message: 'Upload failed with status: ${response.statusCode}',
           code: 'upload-failed',
         );
      }
      
      final responseBody = await response.stream.bytesToString();
      final jsonResponse = jsonDecode(responseBody);
      final downloadUrl = jsonResponse['url'] as String;
      
      if (onProgress != null) onProgress(1.0);

      _logger.i('Post media uploaded successfully: $filePath');

      return PostUploadResult(
        downloadUrl: downloadUrl,
        storagePath: filePath,
        fileSize: fileSize,
      );
    } on DatabaseException {
      rethrow;
    } catch (e, stack) {
      _logger.e('Upload error', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to upload file',
        code: 'upload-failed',
        originalError: e,
      );
    }
  }

  Future<void> deleteFile(String storagePath) async {
    _logger.d('Post media deleted mocked: $storagePath');
  }

  Future<void> deleteAllPostMedia({
    required String authorId,
    required String postId,
  }) async {
    _logger.d('deleteAllPostMedia mocked');
  }

  /// Generates a temporary post ID for use during upload
  /// (before the Firestore document is created).
  String generatePostId() => _uuid.v4();

  // ─── Validation ───────────────────────────────────────────────────────

  void _validateFileSize(int fileSize, String storagePath) {
    const int maxImageSize = 10 * 1024 * 1024; // 10MB (post-compression)
    const int maxVideoSize = 50 * 1024 * 1024; // 50MB (post-compression)
    const int maxThumbnailSize = 5 * 1024 * 1024; // 5MB

    int maxSize;
    String fileType;

    if (storagePath.contains('images')) {
      maxSize = maxImageSize;
      fileType = 'Image';
    } else if (storagePath.contains('videos')) {
      maxSize = maxVideoSize;
      fileType = 'Video';
    } else if (storagePath.contains('thumbnails')) {
      maxSize = maxThumbnailSize;
      fileType = 'Thumbnail';
    } else {
      return;
    }

    if (fileSize > maxSize) {
      final maxSizeMB = (maxSize / (1024 * 1024)).toStringAsFixed(0);
      final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
      throw DatabaseException(
        message:
            '$fileType file is too large ($fileSizeMB MB). Maximum size is $maxSizeMB MB',
        code: 'file-too-large',
      );
    }
  }

  void _validateFileExtension(String extension, String storagePath) {
    final ext = extension.toLowerCase();

    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    const videoExtensions = ['.mp4', '.mov', '.avi'];
    const thumbnailExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

    List<String> allowedExtensions;
    String fileType;

    if (storagePath.contains('images')) {
      allowedExtensions = imageExtensions;
      fileType = 'Image';
    } else if (storagePath.contains('videos')) {
      allowedExtensions = videoExtensions;
      fileType = 'Video';
    } else if (storagePath.contains('thumbnails')) {
      allowedExtensions = thumbnailExtensions;
      fileType = 'Thumbnail';
    } else {
      return;
    }

    if (!allowedExtensions.contains(ext)) {
      throw DatabaseException(
        message:
            '$fileType file type not supported. Allowed types: ${allowedExtensions.join(', ')}',
        code: 'invalid-file-type',
      );
    }
  }

  /// Magic-byte signatures for validating file content.
  static const Map<String, List<List<int>>> _magicBytes = {
    '.jpg': [
      [0xFF, 0xD8, 0xFF],
    ],
    '.jpeg': [
      [0xFF, 0xD8, 0xFF],
    ],
    '.png': [
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    ],
    '.gif': [
      [0x47, 0x49, 0x46, 0x38],
    ],
    '.webp': [
      [0x52, 0x49, 0x46, 0x46],
    ],
    '.mp4': [
      [0x00, 0x00, 0x00],
    ],
    '.avi': [
      [0x52, 0x49, 0x46, 0x46],
    ],
  };

  Future<void> _validateMagicBytes(File file, String extension) async {
    final ext = extension.toLowerCase();
    final signatures = _magicBytes[ext];

    // Skip for formats without reliable magic bytes (e.g. .mov)
    if (signatures == null) return;

    final maxLen =
        signatures.fold<int>(0, (m, s) => s.length > m ? s.length : m);
    final Uint8List header;
    final raf = await file.open(mode: FileMode.read);
    try {
      header = (await raf.read(maxLen.clamp(0, 16)));
    } finally {
      await raf.close();
    }

    final matches = signatures.any((sig) {
      if (header.length < sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (header[i] != sig[i]) return false;
      }
      return true;
    });

    if (!matches) {
      throw DatabaseException(
        message: 'File content does not match its extension ($ext)',
        code: 'invalid-file-content',
      );
    }
  }

  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  // Removed _mapStorageException
}
