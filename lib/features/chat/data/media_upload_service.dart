import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

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

  static const _uuid = Uuid();

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

      // Validate file content matches extension via magic-byte check
      await _validateMagicBytes(file, extension, storagePath);

      // Create unique file path with a UUID to prevent path enumeration.
      // Metadata still records senderId and timestamp for auditing.
      final fileId = _uuid.v4();
      final filePath =
          '$storagePath/$conversationId/$fileId$extension';

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

      // Clean up temp source file after successful upload
      _deleteTempFile(file);

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

  /// Magic-byte signatures for validating file content matches its extension.
  static const Map<String, List<List<int>>> _magicBytes = {
    // Images
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
      [0x47, 0x49, 0x46, 0x38], // GIF8
    ],
    '.webp': [
      [0x52, 0x49, 0x46, 0x46], // RIFF (+ WEBP at offset 8)
    ],
    // Audio
    '.mp3': [
      [0xFF, 0xFB], // MPEG sync
      [0xFF, 0xF3],
      [0xFF, 0xF2],
      [0x49, 0x44, 0x33], // ID3 tag
    ],
    '.wav': [
      [0x52, 0x49, 0x46, 0x46], // RIFF
    ],
    '.ogg': [
      [0x4F, 0x67, 0x67, 0x53], // OggS
    ],
    '.m4a': [
      [0x00, 0x00, 0x00], // ftyp box (variable offset)
    ],
    '.aac': [
      [0xFF, 0xF1],
      [0xFF, 0xF9],
    ],
    // Documents
    '.pdf': [
      [0x25, 0x50, 0x44, 0x46], // %PDF
    ],
    '.doc': [
      [0xD0, 0xCF, 0x11, 0xE0], // OLE compound file
    ],
    '.docx': [
      [0x50, 0x4B, 0x03, 0x04], // PK (ZIP)
    ],
    '.xls': [
      [0xD0, 0xCF, 0x11, 0xE0], // OLE compound file
    ],
    '.xlsx': [
      [0x50, 0x4B, 0x03, 0x04], // PK (ZIP)
    ],
    // Video
    '.mp4': [
      [0x00, 0x00, 0x00], // ftyp box (variable offset)
    ],
    '.avi': [
      [0x52, 0x49, 0x46, 0x46], // RIFF
    ],
  };

  /// Validates that the file's leading bytes match the expected magic bytes
  /// for the given extension. This prevents a renamed file from bypassing
  /// extension-based content-type rules.
  Future<void> _validateMagicBytes(
    File file,
    String extension,
    String storagePath,
  ) async {
    final ext = extension.toLowerCase();
    final signatures = _magicBytes[ext];

    // Skip validation for formats without reliable magic bytes (e.g. .txt, .mov)
    if (signatures == null) return;

    // Read enough leading bytes to check the longest signature
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
      for (int i = 0; i < sig.length; i++) {
        if (header[i] != sig[i]) return false;
      }
      return true;
    });

    if (!matches) {
      throw const DatabaseException(
        message:
            'File content does not match its extension. The file may be corrupted or renamed.',
        code: 'invalid-file-content',
      );
    }
  }

  /// Deletes a temporary source file after a successful upload.
  /// Runs asynchronously and does not throw on failure.
  void _deleteTempFile(File file) {
    Future(() async {
      try {
        if (await file.exists()) {
          await file.delete();
          _logger.d('Temp file deleted: ${file.path}');
        }
      } catch (e) {
        _logger.w('Failed to delete temp file: ${file.path}', error: e);
      }
    });
  }
}
