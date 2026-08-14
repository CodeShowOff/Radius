import 'dart:io';
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../core/error/exceptions.dart';
import '../../chat/data/media_upload_service.dart';

/// Service for uploading media files to Firebase Storage for group chats.
///
/// Uses `group_media/` storage paths (vs `chat_media/` for 1:1 chats).
/// Storage rules enforce group membership via `isAnyGroupMember()`.
class GroupMediaUploadService {
  final Logger _logger;
  static const String _backendUrl = 'http://192.168.13.103:3000/api/upload';

  static const String _imagesPath = 'group_media/images';
  static const String _audioPath = 'group_media/audio';
  static const String _documentsPath = 'group_media/documents';

  static const _uuid = Uuid();

  GroupMediaUploadService({
    Logger? logger,
  })  : _logger = logger ?? Logger();

  /// Uploads an image file for a group chat.
  Future<UploadResult> uploadImage({
    required File file,
    required String groupId,
    required String senderId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _imagesPath,
      groupId: groupId,
      senderId: senderId,
      onProgress: onProgress,
    );
  }

  /// Uploads an audio file (voice message) for a group chat.
  Future<UploadResult> uploadAudio({
    required File file,
    required String groupId,
    required String senderId,
    int? duration,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _audioPath,
      groupId: groupId,
      senderId: senderId,
      duration: duration,
      onProgress: onProgress,
    );
  }

  /// Uploads a document file for a group chat.
  Future<UploadResult> uploadDocument({
    required File file,
    required String groupId,
    required String senderId,
    void Function(double progress)? onProgress,
  }) async {
    return _uploadFile(
      file: file,
      storagePath: _documentsPath,
      groupId: groupId,
      senderId: senderId,
      onProgress: onProgress,
    );
  }

  /// Generic file upload handler for group media.
  Future<UploadResult> _uploadFile({
    required File file,
    required String storagePath,
    required String groupId,
    required String senderId,
    int? duration,
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
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.'))
          : '';

      _validateFileSize(fileSize, storagePath);
      _validateFileExtension(extension, storagePath);
      await _validateMagicBytes(file, extension);

      final fileId = _uuid.v4();
      final filePath = '$storagePath/$groupId/$fileId$extension';

      _logger.d('Uploading group file to: $filePath ($fileSize bytes)');

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

      _logger.i('Group file uploaded successfully: $downloadUrl');

      _deleteTempFile(file);

      return UploadResult(
        downloadUrl: downloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        duration: duration,
      );
    } catch (e, stack) {
      if (e is DatabaseException) rethrow;
      _logger.e('Upload error', error: e, stackTrace: stack);
      throw DatabaseException(
        message: 'Failed to upload file',
        code: 'upload-failed',
        originalError: e,
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
      default:
        return 'application/octet-stream';
    }
  }

  // Removed _mapStorageException

  void _validateFileSize(int fileSize, String storagePath) {
    const int maxImageSize = 20 * 1024 * 1024;
    const int maxAudioSize = 50 * 1024 * 1024;
    const int maxDocumentSize = 100 * 1024 * 1024;

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
    const audioExtensions = ['.mp3', '.m4a', '.aac', '.wav', '.ogg'];
    const documentExtensions = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.txt'];

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

  static const Map<String, List<List<int>>> _magicBytes = {
    '.jpg': [[0xFF, 0xD8, 0xFF]],
    '.jpeg': [[0xFF, 0xD8, 0xFF]],
    '.png': [[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]],
    '.gif': [[0x47, 0x49, 0x46, 0x38]],
    '.webp': [[0x52, 0x49, 0x46, 0x46]],
    '.mp3': [[0xFF, 0xFB], [0xFF, 0xF3], [0xFF, 0xF2], [0x49, 0x44, 0x33]],
    '.wav': [[0x52, 0x49, 0x46, 0x46]],
    '.ogg': [[0x4F, 0x67, 0x67, 0x53]],
    '.m4a': [[0x00, 0x00, 0x00]],
    '.aac': [[0xFF, 0xF1], [0xFF, 0xF9]],
    '.pdf': [[0x25, 0x50, 0x44, 0x46]],
    '.doc': [[0xD0, 0xCF, 0x11, 0xE0]],
    '.docx': [[0x50, 0x4B, 0x03, 0x04]],
    '.xls': [[0xD0, 0xCF, 0x11, 0xE0]],
    '.xlsx': [[0x50, 0x4B, 0x03, 0x04]],
  };

  Future<void> _validateMagicBytes(File file, String extension) async {
    final ext = extension.toLowerCase();
    final signatures = _magicBytes[ext];
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
