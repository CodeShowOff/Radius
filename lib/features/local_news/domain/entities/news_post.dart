import 'package:equatable/equatable.dart';

import '../../../posts/domain/entities/media_item.dart';

/// Domain entity representing a local news post tied to a geographic location.
class NewsPost extends Equatable {
  /// Unique post ID (Firestore auto-generated).
  final String id;

  /// User ID of the post author.
  final String authorId;

  /// Text content or caption (optional, max 2000 chars).
  final String? text;

  /// Ordered list of media items (max 10).
  final List<MediaItem> mediaItems;

  /// Denormalized author display name.
  final String authorName;

  /// Denormalized author photo URL.
  final String? authorPhotoUrl;

  // ─── Location fields ──────────────────────────────────────────────────

  /// Latitude where the post was created.
  final double latitude;

  /// Longitude where the post was created.
  final double longitude;

  /// GeoHash for proximity queries.
  final String geoHash;

  /// District / sub-administrative area (from GPS geocoding).
  final String district;

  /// City name.
  final String city;

  /// Locality / sub-locality / neighborhood.
  final String locality;

  /// Country name.
  final String country;

  // ─── Metadata ─────────────────────────────────────────────────────────

  /// When the post was created.
  final DateTime createdAt;

  /// When the post was last updated.
  final DateTime updatedAt;

  /// Denormalized like count (maintained by Cloud Functions).
  final int likeCount;

  /// Denormalized comment count (maintained by Cloud Functions).
  final int commentCount;

  /// Post type: 'post' for regular news posts, 'reel' for short-form videos.
  final String postType;

  /// Dynamic trending score based on time decay and engagement.
  final double trendingScore;

  const NewsPost({
    required this.id,
    required this.authorId,
    this.text,
    this.mediaItems = const [],
    required this.authorName,
    this.authorPhotoUrl,
    required this.latitude,
    required this.longitude,
    required this.geoHash,
    required this.district,
    required this.city,
    required this.locality,
    required this.country,
    required this.createdAt,
    required this.updatedAt,
    this.likeCount = 0,
    this.commentCount = 0,
    this.postType = 'post',
    this.trendingScore = 0.0,
  });

  /// Whether this post is a reel (short-form video).
  bool get isReel => postType == 'reel';

  /// Whether the post has any media.
  bool get hasMedia => mediaItems.isNotEmpty;

  /// Whether the post is text-only.
  bool get isTextOnly => mediaItems.isEmpty && text != null && text!.isNotEmpty;

  /// Whether the post has multiple media items.
  bool get hasMultipleMedia => mediaItems.length > 1;

  /// Human-readable location label.
  String get locationLabel {
    if (city.isNotEmpty && country.isNotEmpty) {
      return '$city, $country';
    }
    if (city.isNotEmpty) return city;
    return country;
  }

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  NewsPost copyWith({
    String? id,
    String? authorId,
    Object? text = _sentinel,
    List<MediaItem>? mediaItems,
    String? authorName,
    Object? authorPhotoUrl = _sentinel,
    double? latitude,
    double? longitude,
    String? geoHash,
    String? district,
    String? city,
    String? locality,
    String? country,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? likeCount,
    int? commentCount,
    String? postType,
    double? trendingScore,
  }) {
    return NewsPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      text: text == _sentinel ? this.text : text as String?,
      mediaItems: mediaItems ?? this.mediaItems,
      authorName: authorName ?? this.authorName,
      authorPhotoUrl: authorPhotoUrl == _sentinel
          ? this.authorPhotoUrl
          : authorPhotoUrl as String?,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      geoHash: geoHash ?? this.geoHash,
      district: district ?? this.district,
      city: city ?? this.city,
      locality: locality ?? this.locality,
      country: country ?? this.country,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      postType: postType ?? this.postType,
      trendingScore: trendingScore ?? this.trendingScore,
    );
  }

  @override
  List<Object?> get props => [
        id,
        authorId,
        text,
        mediaItems,
        authorName,
        authorPhotoUrl,
        latitude,
        longitude,
        geoHash,
        district,
        city,
        locality,
        country,
        createdAt,
        updatedAt,
        likeCount,
        commentCount,
        postType,
        trendingScore,
      ];
}
