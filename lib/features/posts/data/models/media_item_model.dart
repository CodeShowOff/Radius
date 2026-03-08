import '../../domain/entities/media_item.dart';

/// Firestore serialization for MediaItem entity.
class MediaItemModel {
  final String url;
  final PostMediaType type;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final int? durationMs;
  final String storagePath;

  const MediaItemModel({
    required this.url,
    required this.type,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.durationMs,
    required this.storagePath,
  });

  /// Creates model from Firestore map.
  factory MediaItemModel.fromMap(Map<String, dynamic> map) {
    return MediaItemModel(
      url: map['url'] as String,
      type: _parseMediaType(map['type'] as String),
      thumbnailUrl: map['thumbnailUrl'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      durationMs: map['durationMs'] as int?,
      storagePath: map['storagePath'] as String,
    );
  }

  /// Creates model from domain entity.
  factory MediaItemModel.fromEntity(MediaItem item) {
    return MediaItemModel(
      url: item.url,
      type: item.type,
      thumbnailUrl: item.thumbnailUrl,
      width: item.width,
      height: item.height,
      durationMs: item.durationMs,
      storagePath: item.storagePath,
    );
  }

  /// Converts to Firestore map.
  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'type': type.name,
      'thumbnailUrl': thumbnailUrl,
      'width': width,
      'height': height,
      'durationMs': durationMs,
      'storagePath': storagePath,
    };
  }

  /// Converts to domain entity.
  MediaItem toEntity() {
    return MediaItem(
      url: url,
      type: type,
      thumbnailUrl: thumbnailUrl,
      width: width,
      height: height,
      durationMs: durationMs,
      storagePath: storagePath,
    );
  }

  static PostMediaType _parseMediaType(String type) {
    return PostMediaType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => PostMediaType.image,
    );
  }
}
