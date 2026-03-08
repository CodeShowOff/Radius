import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import '../../../../core/error/exceptions.dart';

/// Result of a media optimization operation.
class OptimizedMedia {
  final File file;
  final int originalSize;
  final int optimizedSize;

  const OptimizedMedia({
    required this.file,
    required this.originalSize,
    required this.optimizedSize,
  });
}

/// Service that optimizes media files before upload.
///
/// - **Images**: compresses to JPEG, enforces max 10 MB, resizes to fit 1920px.
/// - **Videos**: enforces max ~60 s duration, compresses via re‑encoding,
///   enforces max 50 MB after compression.
/// - **Reels**: enforces max 30 s duration, validates 9:16 aspect ratio,
///   same compression pipeline, max 50 MB.
class MediaOptimizer {
  final Logger _logger;

  /// Max image file size after compression (10 MB).
  static const int maxImageBytes = 10 * 1024 * 1024;

  /// Max video file size after compression (50 MB).
  static const int maxVideoBytes = 50 * 1024 * 1024;

  /// Max video duration in seconds.
  static const int maxVideoDurationSeconds = 60;

  /// Max reel duration in seconds.
  static const int maxReelDurationSeconds = 30;

  /// Expected reel aspect ratio (9:16 = 0.5625).
  static const double reelAspectRatio = 9 / 16;

  /// Tolerance for reel aspect ratio validation (±5%).
  static const double reelAspectRatioTolerance = 0.05;

  /// Target image dimension (longest side).
  static const int imageMaxDimension = 1920;

  MediaOptimizer({Logger? logger}) : _logger = logger ?? Logger();

  // ─── Image ──────────────────────────────────────────────────────────

  /// Compresses an image file. Returns the optimized file.
  /// Throws [DatabaseException] if the result still exceeds limits.
  Future<OptimizedMedia> optimizeImage(File file) async {
    final originalSize = await file.length();
    _logger.d('Optimizing image: ${_mb(originalSize)} MB');

    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/opt_${DateTime.now().millisecondsSinceEpoch}.jpg';

    // First pass — quality 85
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 85,
      minWidth: imageMaxDimension,
      minHeight: imageMaxDimension,
      keepExif: false,
    );

    if (result == null) {
      // Compression failed — fall back to original
      _logger.w('Image compression returned null, using original');
      return OptimizedMedia(
        file: file,
        originalSize: originalSize,
        optimizedSize: originalSize,
      );
    }

    var optimizedSize = await result.length();

    // Second pass at lower quality if still too large
    if (optimizedSize > maxImageBytes) {
      final retryPath =
          '${tempDir.path}/opt2_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final retryResult = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        retryPath,
        quality: 60,
        minWidth: 1280,
        minHeight: 1280,
        keepExif: false,
      );

      if (retryResult != null) {
        // Delete first attempt
        try {
          await File(result.path).delete();
        } catch (_) {}
        result = retryResult;
        optimizedSize = await result.length();
      }
    }

    if (optimizedSize > maxImageBytes) {
      final sizeMB = _mb(optimizedSize);
      throw DatabaseException(
        message:
            'Image is still too large after compression ($sizeMB MB). Maximum is ${maxImageBytes ~/ (1024 * 1024)} MB.',
        code: 'image-too-large',
      );
    }

    _logger.i(
      'Image optimized: ${_mb(originalSize)} MB → ${_mb(optimizedSize)} MB',
    );

    return OptimizedMedia(
      file: File(result.path),
      originalSize: originalSize,
      optimizedSize: optimizedSize,
    );
  }

  // ─── Video ──────────────────────────────────────────────────────────

  /// Validates duration and compresses a video file.
  /// Throws [DatabaseException] if the video exceeds duration or size limits.
  Future<OptimizedMedia> optimizeVideo(File file) async {
    final originalSize = await file.length();
    _logger.d('Optimizing video: ${_mb(originalSize)} MB');

    // Check duration
    final info = await VideoCompress.getMediaInfo(file.path);
    final durationSec = (info.duration ?? 0) / 1000;

    if (durationSec > maxVideoDurationSeconds) {
      throw DatabaseException(
        message:
            'Video is too long (${durationSec.toStringAsFixed(0)}s). Maximum duration is $maxVideoDurationSeconds seconds.',
        code: 'video-too-long',
      );
    }

    // Compress
    final compressed = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
      includeAudio: true,
    );

    if (compressed == null || compressed.file == null) {
      _logger.w('Video compression returned null, using original');
      if (originalSize > maxVideoBytes) {
        throw DatabaseException(
          message:
              'Video file is too large (${_mb(originalSize)} MB). Maximum is ${maxVideoBytes ~/ (1024 * 1024)} MB.',
          code: 'video-too-large',
        );
      }
      return OptimizedMedia(
        file: file,
        originalSize: originalSize,
        optimizedSize: originalSize,
      );
    }

    final optimizedSize = await compressed.file!.length();

    if (optimizedSize > maxVideoBytes) {
      throw DatabaseException(
        message:
            'Video is still too large after compression (${_mb(optimizedSize)} MB). '
            'Try a shorter or lower-resolution video.',
        code: 'video-too-large',
      );
    }

    _logger.i(
      'Video optimized: ${_mb(originalSize)} MB → ${_mb(optimizedSize)} MB',
    );

    return OptimizedMedia(
      file: compressed.file!,
      originalSize: originalSize,
      optimizedSize: optimizedSize,
    );
  }

  /// Generates a thumbnail for a video file.
  Future<File?> generateVideoThumbnail(String videoPath) async {
    try {
      final thumbnailFile = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 75,
        position: -1, // default frame
      );
      return thumbnailFile;
    } catch (e) {
      _logger.e('Failed to generate video thumbnail', error: e);
      return null;
    }
  }

  // ─── Reel ───────────────────────────────────────────────────────────

  /// Validates and compresses a reel video file.
  ///
  /// Enforces:
  /// - Max duration: 30 seconds
  /// - Aspect ratio: 9:16 (vertical, ±5% tolerance)
  /// - Max file size: 50 MB after compression
  ///
  /// Throws [DatabaseException] if the video exceeds limits or has an
  /// invalid aspect ratio.
  Future<OptimizedMedia> optimizeReelVideo(File file) async {
    final originalSize = await file.length();
    _logger.d('Optimizing reel video: ${_mb(originalSize)} MB');

    // Get media info for duration and dimensions
    final info = await VideoCompress.getMediaInfo(file.path);
    final durationSec = (info.duration ?? 0) / 1000;

    if (durationSec > maxReelDurationSeconds) {
      throw DatabaseException(
        message:
            'Reel is too long (${durationSec.toStringAsFixed(0)}s). '
            'Maximum duration is $maxReelDurationSeconds seconds.',
        code: 'reel-too-long',
      );
    }

    // Validate aspect ratio (9:16 portrait)
    final width = info.width?.toDouble() ?? 0;
    final height = info.height?.toDouble() ?? 0;

    if (width <= 0 || height <= 0) {
      throw const DatabaseException(
        message: 'Could not determine video dimensions.',
        code: 'reel-invalid-dimensions',
      );
    }

    final aspectRatio = width / height;
    final lowerBound = reelAspectRatio * (1 - reelAspectRatioTolerance);
    final upperBound = reelAspectRatio * (1 + reelAspectRatioTolerance);

    if (aspectRatio < lowerBound || aspectRatio > upperBound) {
      throw DatabaseException(
        message:
            'Reel must be in 9:16 vertical format. '
            'Current ratio is ${width.toInt()}×${height.toInt()}. '
            'Please record or crop your video in portrait mode.',
        code: 'reel-invalid-aspect-ratio',
      );
    }

    // Compress
    final compressed = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
      includeAudio: true,
    );

    if (compressed == null || compressed.file == null) {
      _logger.w('Reel compression returned null, using original');
      if (originalSize > maxVideoBytes) {
        throw DatabaseException(
          message:
              'Reel file is too large (${_mb(originalSize)} MB). '
              'Maximum is ${maxVideoBytes ~/ (1024 * 1024)} MB.',
          code: 'reel-too-large',
        );
      }
      return OptimizedMedia(
        file: file,
        originalSize: originalSize,
        optimizedSize: originalSize,
      );
    }

    final optimizedSize = await compressed.file!.length();

    if (optimizedSize > maxVideoBytes) {
      throw DatabaseException(
        message:
            'Reel is still too large after compression '
            '(${_mb(optimizedSize)} MB). '
            'Try a shorter or lower-resolution video.',
        code: 'reel-too-large',
      );
    }

    _logger.i(
      'Reel optimized: ${_mb(originalSize)} MB → ${_mb(optimizedSize)} MB',
    );

    return OptimizedMedia(
      file: compressed.file!,
      originalSize: originalSize,
      optimizedSize: optimizedSize,
    );
  }

  /// Cleans up any cached compression artifacts.
  Future<void> dispose() async {
    await VideoCompress.deleteAllCache();
  }

  String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}
