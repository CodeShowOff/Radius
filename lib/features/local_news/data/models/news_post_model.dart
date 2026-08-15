import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../posts/data/models/media_item_model.dart';
import '../../domain/entities/news_post.dart';

/// Firestore model for NewsPost entity.
///
/// Firestore Schema:
/// ```
/// local_news_posts/{postId}
///   - authorId: string
///   - authorName: string
///   - authorPhotoUrl: string?
///   - text: string? (max 2000 chars)
///   - mediaItems: list<map>
///   - location: GeoPoint
///   - geoHash: string
///   - district: string
///   - city: string
///   - locality: string
///   - country: string
///   - postType: string ('post' | 'reel', default 'post')
///   - likeCount: number
///   - commentCount: number
///   - createdAt: timestamp
///   - updatedAt: timestamp
/// ```
class NewsPostModel extends NewsPost {
  const NewsPostModel({
    required super.id,
    required super.authorId,
    super.text,
    super.mediaItems,
    required super.authorName,
    super.authorPhotoUrl,
    required super.latitude,
    required super.longitude,
    required super.geoHash,
    required super.district,
    required super.city,
    required super.locality,
    required super.country,
    required super.createdAt,
    required super.updatedAt,
    super.likeCount,
    super.commentCount,
    super.postType,
    super.trendingScore,
  });

  /// Creates model from Firestore document.
  /// Throws [FormatException] if required fields are missing.
  factory NewsPostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw FormatException('NewsPost document ${doc.id} has no data');
    }

    final authorId = data['authorId'] as String?;
    final createdAt = data['createdAt'] as Timestamp?;
    final updatedAt = data['updatedAt'] as Timestamp?;

    if (authorId == null || createdAt == null || updatedAt == null) {
      throw FormatException(
        'NewsPost document ${doc.id} missing required fields: '
        'authorId=$authorId, createdAt=$createdAt, updatedAt=$updatedAt',
      );
    }

    // Parse media items
    final rawMediaItems = data['mediaItems'] as List<dynamic>? ?? [];
    final mediaItems = rawMediaItems
        .map((item) =>
            MediaItemModel.fromMap(item as Map<String, dynamic>).toEntity())
        .toList();

    // Parse location GeoPoint
    final geoPoint = data['location'] as GeoPoint?;
    final latitude = geoPoint?.latitude ?? 0.0;
    final longitude = geoPoint?.longitude ?? 0.0;

    return NewsPostModel(
      id: doc.id,
      authorId: authorId,
      text: data['text'] as String?,
      mediaItems: mediaItems,
      authorName: data['authorName'] as String? ?? '',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      latitude: latitude,
      longitude: longitude,
      geoHash: data['geoHash'] as String? ?? '',
      district: data['district'] as String? ?? '',
      city: data['city'] as String? ?? '',
      locality: data['locality'] as String? ?? '',
      country: data['country'] as String? ?? '',
      createdAt: createdAt.toDate(),
      updatedAt: updatedAt.toDate(),
      likeCount: (data['likeCount'] as int?) ?? 0,
      commentCount: (data['commentCount'] as int?) ?? 0,
      postType: data['postType'] as String? ?? 'post',
      trendingScore: (data['trendingScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Creates model from a raw map (e.g., from Node.js REST API).
  factory NewsPostModel.fromMap(Map<String, dynamic> data, String docId) {
    final authorId = data['authorId'] as String?;
    
    // Node.js Firestore Timestamps serialize as {_seconds, _nanoseconds}
    DateTime parseTimestamp(dynamic ts) {
      if (ts == null) return DateTime.now();
      if (ts is Map && ts.containsKey('_seconds')) {
        return DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
      }
      if (ts is String) {
        return DateTime.parse(ts);
      }
      return DateTime.now();
    }

    final createdAt = parseTimestamp(data['createdAt']);
    final updatedAt = parseTimestamp(data['updatedAt']);

    if (authorId == null) {
      throw FormatException('NewsPost map missing authorId');
    }

    // Parse media items
    final rawMediaItems = data['mediaItems'] as List<dynamic>? ?? [];
    final mediaItems = rawMediaItems
        .map((item) =>
            MediaItemModel.fromMap(item as Map<String, dynamic>).toEntity())
        .toList();

    // Parse location GeoPoint
    double latitude = 0.0;
    double longitude = 0.0;
    final geoPoint = data['location'];
    if (geoPoint is Map) {
      latitude = (geoPoint['_latitude'] as num?)?.toDouble() ?? 0.0;
      longitude = (geoPoint['_longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return NewsPostModel(
      id: docId,
      authorId: authorId,
      text: data['text'] as String?,
      mediaItems: mediaItems,
      authorName: data['authorName'] as String? ?? '',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      latitude: latitude,
      longitude: longitude,
      geoHash: data['geoHash'] as String? ?? '',
      district: data['district'] as String? ?? '',
      city: data['city'] as String? ?? '',
      locality: data['locality'] as String? ?? '',
      country: data['country'] as String? ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      likeCount: (data['likeCount'] as int?) ?? 0,
      commentCount: (data['commentCount'] as int?) ?? 0,
      postType: data['postType'] as String? ?? 'post',
      trendingScore: (data['trendingScore'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Creates model from domain entity.
  factory NewsPostModel.fromEntity(NewsPost post) {
    return NewsPostModel(
      id: post.id,
      authorId: post.authorId,
      text: post.text,
      mediaItems: post.mediaItems,
      authorName: post.authorName,
      authorPhotoUrl: post.authorPhotoUrl,
      latitude: post.latitude,
      longitude: post.longitude,
      geoHash: post.geoHash,
      district: post.district,
      city: post.city,
      locality: post.locality,
      country: post.country,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
      likeCount: post.likeCount,
      commentCount: post.commentCount,
      postType: post.postType,
      trendingScore: post.trendingScore,
    );
  }

  /// Converts to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorName': _sanitizeField(authorName, maxNameLength),
      'authorPhotoUrl': authorPhotoUrl,
      'text': text != null ? _sanitizeText(text!) : null,
      'mediaItems':
          mediaItems.map((item) => MediaItemModel.fromEntity(item).toMap()).toList(),
      'location': GeoPoint(latitude, longitude),
      'geoHash': geoHash,
      'district': district,
      'city': city,
      'locality': locality,
      'country': country,
      'postType': postType,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'trendingScore': trendingScore,
    };
  }

  /// Converts to domain entity.
  NewsPost toEntity() {
    return NewsPost(
      id: id,
      authorId: authorId,
      text: text,
      mediaItems: mediaItems,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      latitude: latitude,
      longitude: longitude,
      geoHash: geoHash,
      district: district,
      city: city,
      locality: locality,
      country: country,
      createdAt: createdAt,
      updatedAt: updatedAt,
      likeCount: likeCount,
      commentCount: commentCount,
      postType: postType,
      trendingScore: trendingScore,
    );
  }

  // ─── Validation constants ─────────────────────────────────────────────

  static const int maxTextLength = 2000;
  static const int maxNameLength = 50;
  static const int maxMediaItems = 10;

  /// Sanitizes post text: removes control characters, trims, enforces max length.
  static String _sanitizeText(String value) {
    var sanitized =
        value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    sanitized = sanitized.trim();
    if (sanitized.length > maxTextLength) {
      sanitized = sanitized.substring(0, maxTextLength);
    }
    return sanitized;
  }

  /// Sanitizes a field: removes control characters, trims, enforces max length.
  static String _sanitizeField(String value, int maxLength) {
    var sanitized =
        value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    sanitized = sanitized.trim();
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }
    return sanitized;
  }

  /// Generates a simple geohash for the given coordinates.
  static String generateGeoHash(double latitude, double longitude) {
    final latPart =
        ((latitude + 90) * 1000).toInt().toString().padLeft(6, '0');
    final lonPart =
        ((longitude + 180) * 1000).toInt().toString().padLeft(6, '0');
    return '$latPart$lonPart';
  }
}
