import 'package:equatable/equatable.dart';

/// Type of media in a post.
enum PostMediaType {
  image,
  video,
}

/// Entity representing a single media item within a post.
class MediaItem extends Equatable {
  /// Download URL from Firebase Storage.
  final String url;

  /// Type of media (image or video).
  final PostMediaType type;

  /// Thumbnail URL for videos.
  final String? thumbnailUrl;

  /// Original width of the media.
  final int? width;

  /// Original height of the media.
  final int? height;

  /// Duration in milliseconds (for videos).
  final int? durationMs;

  /// Firebase Storage path for cleanup/deletion.
  final String storagePath;

  const MediaItem({
    required this.url,
    required this.type,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.durationMs,
    required this.storagePath,
  });

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  MediaItem copyWith({
    String? url,
    PostMediaType? type,
    Object? thumbnailUrl = _sentinel,
    Object? width = _sentinel,
    Object? height = _sentinel,
    Object? durationMs = _sentinel,
    String? storagePath,
  }) {
    return MediaItem(
      url: url ?? this.url,
      type: type ?? this.type,
      thumbnailUrl:
          thumbnailUrl == _sentinel ? this.thumbnailUrl : thumbnailUrl as String?,
      width: width == _sentinel ? this.width : width as int?,
      height: height == _sentinel ? this.height : height as int?,
      durationMs:
          durationMs == _sentinel ? this.durationMs : durationMs as int?,
      storagePath: storagePath ?? this.storagePath,
    );
  }

  @override
  List<Object?> get props => [
        url,
        type,
        thumbnailUrl,
        width,
        height,
        durationMs,
        storagePath,
      ];
}
