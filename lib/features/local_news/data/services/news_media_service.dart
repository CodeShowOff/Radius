import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/exceptions.dart';

/// Result of a news media upload operation.
class NewsUploadResult {
  final String downloadUrl;
  final String storagePath;
  final int fileSize;

  const NewsUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.fileSize,
  });
}

/// Service for uploading and deleting local news media files in Firebase Storage.
///
/// Storage paths:
/// - `local_news_media/images/{authorId}/{postId}/{uuid}.ext` (max 10MB)
/// - `local_news_media/videos/{authorId}/{postId}/{uuid}.ext` (max 50MB)
/// - `local_news_media/reels/{authorId}/{postId}/{uuid}.ext` (max 50MB)
/// - `local_news_media/thumbnails/{authorId}/{postId}/{uuid}.jpg` (max 5MB)
class NewsMediaService {
  final FirebaseStorage _storage;
  final Logger _logger;

  static const String _imagesPath = 'local_news_media/images';
  static const String _videosPath = 'local_news_media/videos';
  static const String _reelsPath = 'local_news_media/reels';
  static const String _thumbnailsPath = 'local_news_media/thumbnails';

  static const _uuid = Uuid();

  NewsMediaService({
    FirebaseStorage? storage,
    Logger? logger,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _logger = logger ?? Logger();

  /// Uploads a news post image and returns the download URL + storage path.
  Future<NewsUploadResult> uploadImage({
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

  /// Uploads a news post video and returns the download URL + storage path.
  Future<NewsUploadResult> uploadVideo({
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
  Future<NewsUploadResult> uploadThumbnail({
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

  /// Uploads a reel video and returns the download URL + storage path.
  Future<NewsUploadResult> uploadReel({
    required File file,
    required String authorId,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _reelsPath,
      authorId: authorId,
      postId: postId,
      onProgress: onProgress,
    );
  }

  /// Generic file upload handler.
  Future<NewsUploadResult> _uploadFile({
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

      _logger.d('Uploading news media to: $filePath ($fileSize bytes)');

      final ref = _storage.ref().child(filePath);
      final metadata = SettableMetadata(
        contentType: _getContentType(extension),
        customMetadata: {
          'authorId': authorId,
          'postId': postId,
          'uploadedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      final uploadTask = ref.putFile(file, metadata);

      if (onProgress != null) {
        uploadTask.snapshotEvents.listen(
          (TaskSnapshot snapshot) {
            final progress = snapshot.bytesTransferred / snapshot.totalBytes;
            onProgress(progress);
          },
          onError: (error) {
            _logger.e('Upload progress error', error: error);
          },
        );
      }

      final snapshot = await uploadTask;

      if (snapshot.state != TaskState.success) {
        throw DatabaseException(
          message: 'Upload failed with state: ${snapshot.state}',
          code: 'upload-failed',
        );
      }

      final downloadUrl = await ref.getDownloadURL();

      _logger.i('News media uploaded successfully: $filePath');

      return NewsUploadResult(
        downloadUrl: downloadUrl,
        storagePath: filePath,
        fileSize: fileSize,
      );
    } on FirebaseException catch (e, stack) {
      _logger.e('Firebase upload error', error: e, stackTrace: stack);
      throw _mapStorageException(e);
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

  /// Deletes a media file from storage by its path.
  Future<void> deleteFile(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.delete();
      _logger.d('News media deleted: $storagePath');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error deleting news media', error: e, stackTrace: stack);
      // Don't throw — file might already be deleted
    }
  }

  /// Deletes all media files for a news post.
  Future<void> deleteAllPostMedia({
    required String authorId,
    required String postId,
  }) async {
    final paths = [
      '$_imagesPath/$authorId/$postId',
      '$_videosPath/$authorId/$postId',
      '$_reelsPath/$authorId/$postId',
      '$_thumbnailsPath/$authorId/$postId',
    ];

    for (final path in paths) {
      try {
        final listResult = await _storage.ref().child(path).listAll();
        for (final item in listResult.items) {
          await item.delete();
        }
      } on FirebaseException catch (e) {
        if (e.code != 'storage/object-not-found') {
          _logger.e('Error cleaning up news media at $path', error: e);
        }
      }
    }
  }

  /// Generates a temporary post ID for use during upload
  /// (before the Firestore document is created).
  String generatePostId() => _uuid.v4();

  // ─── Validation ───────────────────────────────────────────────────────

  void _validateFileSize(int fileSize, String storagePath) {
    const int maxImageSize = 10 * 1024 * 1024; // 10MB
    const int maxVideoSize = 50 * 1024 * 1024; // 50MB
    const int maxThumbnailSize = 5 * 1024 * 1024; // 5MB

    int maxSize;
    String fileType;

    if (storagePath.contains('images')) {
      maxSize = maxImageSize;
      fileType = 'Image';
    } else if (storagePath.contains('reels')) {
      maxSize = maxVideoSize;
      fileType = 'Reel';
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
    } else if (storagePath.contains('reels')) {
      allowedExtensions = videoExtensions;
      fileType = 'Reel';
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

  DatabaseException _mapStorageException(FirebaseException e) {
    String message;
    switch (e.code) {
      case 'storage/unauthorized':
        message = 'Unauthorized to upload file';
        break;
      case 'storage/canceled':
        message = 'Upload was cancelled';
        break;
      case 'storage/unknown':
        message = 'Unknown error occurred during upload';
        break;
      case 'storage/object-not-found':
        message = 'File not found';
        break;
      case 'storage/quota-exceeded':
        message = 'Storage quota exceeded';
        break;
      case 'storage/unauthenticated':
        message = 'User not authenticated';
        break;
      case 'storage/retry-limit-exceeded':
        message = 'Upload retry limit exceeded';
        break;
      default:
        message = e.message ?? 'Storage error occurred';
    }

    return DatabaseException(
      message: message,
      code: e.code,
      originalError: e,
    );
  }
}
