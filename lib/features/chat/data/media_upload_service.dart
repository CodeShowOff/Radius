import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';

import '../../../core/error/exceptions.dart';

/// Result of a media upload operation.
class UploadResult {
  final String downloadUrl;
  final String fileName;
  final int fileSize;
  final int? duration; // For audio/video files

  const UploadResult({
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
    this.duration,
  });
}

/// Service for uploading media files to Firebase Storage.
///
/// Handles:
/// - Image uploads (from camera/gallery)
/// - Audio uploads (voice messages)
/// - Document uploads
/// - Sticker uploads
/// - Progress tracking
/// - Error handling with retry logic
class MediaUploadService {
  final FirebaseStorage _storage;
  final Logger _logger;

  // Storage paths
  static const String _imagesPath = 'chat_media/images';
  static const String _audioPath = 'chat_media/audio';
  static const String _documentsPath = 'chat_media/documents';
  static const String _stickersPath = 'chat_media/stickers';

  MediaUploadService({
    FirebaseStorage? storage,
    Logger? logger,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _logger = logger ?? Logger();

  /// Uploads an image file and returns the download URL.
  Future<UploadResult> uploadImage({
    required File file,
    required String conversationId,
    required String senderId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _imagesPath,
      conversationId: conversationId,
      senderId: senderId,
      onProgress: onProgress,
    );
  }

  /// Uploads an audio file (voice message) and returns the download URL.
  Future<UploadResult> uploadAudio({
    required File file,
    required String conversationId,
    required String senderId,
    int? duration,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _audioPath,
      conversationId: conversationId,
      senderId: senderId,
      duration: duration,
      onProgress: onProgress,
    );
  }

  /// Uploads a document file and returns the download URL.
  Future<UploadResult> uploadDocument({
    required File file,
    required String conversationId,
    required String senderId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _documentsPath,
      conversationId: conversationId,
      senderId: senderId,
      onProgress: onProgress,
    );
  }

  /// Uploads a sticker file and returns the download URL.
  Future<UploadResult> uploadSticker({
    required File file,
    required String conversationId,
    required String senderId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _stickersPath,
      conversationId: conversationId,
      senderId: senderId,
      onProgress: onProgress,
    );
  }

  /// Generic file upload handler.
  Future<UploadResult> _uploadFile({
    required File file,
    required String storagePath,
    required String conversationId,
    required String senderId,
    int? duration,
    void Function(double progress)? onProgress,
  }) async {
    try {
      // Validate file exists
      if (!await file.exists()) {
        throw const DatabaseException(
          message: 'File does not exist',
          code: 'file-not-found',
        );
      }

      // Get file info
      final fileSize = await file.length();
      final fileName = file.path.split(Platform.pathSeparator).last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';

      // Validate file size based on storage path
      _validateFileSize(fileSize, storagePath);

      // Validate file extension for the storage path
      _validateFileExtension(extension, storagePath);

      // Create unique file path: storagePath/conversationId/senderId_timestamp.ext
      final filePath =
          '$storagePath/$conversationId/${senderId}_$timestamp$extension';

      _logger.d('Uploading file to: $filePath ($fileSize bytes)');

      // Create reference and metadata
      final ref = _storage.ref().child(filePath);
      final metadata = SettableMetadata(
        contentType: _getContentType(extension),
        customMetadata: {
          'conversationId': conversationId,
          'senderId': senderId,
          'uploadedAt': timestamp.toString(),
          if (duration != null) 'duration': duration.toString(),
        },
      );

      // Upload file with progress tracking
      final uploadTask = ref.putFile(file, metadata);

      // Listen to progress
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

      // Wait for upload to complete
      final snapshot = await uploadTask;

      if (snapshot.state != TaskState.success) {
        throw DatabaseException(
          message: 'Upload failed with state: ${snapshot.state}',
          code: 'upload-failed',
        );
      }

      // Get download URL
      final downloadUrl = await ref.getDownloadURL();

      _logger.i('File uploaded successfully: $downloadUrl');

      return UploadResult(
        downloadUrl: downloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        duration: duration,
      );
    } on FirebaseException catch (e, stack) {
      _logger.e('Firebase upload error', error: e, stackTrace: stack);
      throw _mapStorageException(e);
    } catch (e, stack) {
      _logger.e('Upload error', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to upload file',
        code: 'upload-failed',
        originalError: e,
      );
    }
  }

  /// Deletes a media file from storage.
  Future<void> deleteFile(String downloadUrl) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
      _logger.d('File deleted: $downloadUrl');
    } on FirebaseException catch (e, stack) {
      _logger.e('Error deleting file', error: e, stackTrace: stack);
      // Don't throw - file might already be deleted
    }
  }

  /// Gets the content type based on file extension.
  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      // Images
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';

      // Audio
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.wav':
        return 'audio/wav';
      case '.ogg':
        return 'audio/ogg';

      // Documents
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.txt':
        return 'text/plain';

      // Video
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

  /// Maps Firebase Storage exceptions to DatabaseException.
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
      case 'storage/bucket-not-found':
        message = 'Storage bucket not found';
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

  /// Validates file size based on storage path (images: 20MB, audio: 50MB, documents: 100MB, stickers: 5MB)
  void _validateFileSize(int fileSize, String storagePath) {
    const int maxImageSize = 20 * 1024 * 1024; // 20MB
    const int maxAudioSize = 50 * 1024 * 1024; // 50MB
    const int maxDocumentSize = 100 * 1024 * 1024; // 100MB
    const int maxStickerSize = 5 * 1024 * 1024; // 5MB

    int maxSize;
    String fileType;

    if (storagePath.contains('images')) {
      maxSize = maxImageSize;
      fileType = 'Image';
    } else if (storagePath.contains('audio')) {
      maxSize = maxAudioSize;
      fileType = 'Audio';
    } else if (storagePath.contains('documents')) {
      maxSize = maxDocumentSize;
      fileType = 'Document';
    } else if (storagePath.contains('stickers')) {
      maxSize = maxStickerSize;
      fileType = 'Sticker';
    } else {
      return; // Unknown type, skip validation
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

  /// Validates file extension matches the expected type for the storage path
  void _validateFileExtension(String extension, String storagePath) {
    final ext = extension.toLowerCase();

    // Define allowed extensions for each type
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
    const audioExtensions = ['.mp3', '.m4a', '.aac', '.wav', '.ogg'];
    const documentExtensions = [
      '.pdf',
      '.doc',
      '.docx',
      '.xls',
      '.xlsx',
      '.txt'
    ];
    const stickerExtensions = ['.png', '.webp', '.gif'];

    List<String> allowedExtensions;
    String fileType;

    if (storagePath.contains('images')) {
      allowedExtensions = imageExtensions;
      fileType = 'Image';
    } else if (storagePath.contains('audio')) {
      allowedExtensions = audioExtensions;
      fileType = 'Audio';
    } else if (storagePath.contains('documents')) {
      allowedExtensions = documentExtensions;
      fileType = 'Document';
    } else if (storagePath.contains('stickers')) {
      allowedExtensions = stickerExtensions;
      fileType = 'Sticker';
    } else {
      return; // Unknown type, skip validation
    }

    if (!allowedExtensions.contains(ext)) {
      throw DatabaseException(
        message:
            '$fileType file type not supported. Allowed types: ${allowedExtensions.join(', ')}',
        code: 'invalid-file-type',
      );
    }
  }
}
