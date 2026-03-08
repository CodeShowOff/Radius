import 'package:equatable/equatable.dart';

import 'media_item.dart';

/// Visibility of a post.
enum PostVisibility {
  /// Visible to all authenticated users.
  public,

  /// Visible only to the author's connections.
  connections,
}

/// Domain entity representing a user post.
class Post extends Equatable {
  /// Unique post ID (Firestore auto-generated).
  final String id;

  /// User ID of the post author.
  final String authorId;

  /// Text content or caption (optional, max 2000 chars).
  final String? text;

  /// Ordered list of media items (max 10).
  final List<MediaItem> mediaItems;

  /// Post visibility setting.
  final PostVisibility visibility;

  /// Denormalized author display name.
  final String authorName;

  /// Denormalized author photo URL.
  final String? authorPhotoUrl;

  /// When the post was created.
  final DateTime createdAt;

  /// When the post was last updated.
  final DateTime updatedAt;

  /// Denormalized like count (maintained by Cloud Functions).
  final int likeCount;

  /// Denormalized comment count (maintained by Cloud Functions).
  final int commentCount;

  const Post({
    required this.id,
    required this.authorId,
    this.text,
    this.mediaItems = const [],
    required this.visibility,
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
    required this.updatedAt,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  /// Whether the post has any media.
  bool get hasMedia => mediaItems.isNotEmpty;

  /// Whether the post is text-only.
  bool get isTextOnly => mediaItems.isEmpty && text != null && text!.isNotEmpty;

  /// Whether the post has multiple media items.
  bool get hasMultipleMedia => mediaItems.length > 1;

  /// Sentinel value for explicitly setting nullable fields to null in copyWith.
  static const _sentinel = Object();

  Post copyWith({
    String? id,
    String? authorId,
    Object? text = _sentinel,
    List<MediaItem>? mediaItems,
    PostVisibility? visibility,
    String? authorName,
    Object? authorPhotoUrl = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? likeCount,
    int? commentCount,
  }) {
    return Post(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      text: text == _sentinel ? this.text : text as String?,
      mediaItems: mediaItems ?? this.mediaItems,
      visibility: visibility ?? this.visibility,
      authorName: authorName ?? this.authorName,
      authorPhotoUrl: authorPhotoUrl == _sentinel
          ? this.authorPhotoUrl
          : authorPhotoUrl as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
    );
  }

  @override
  List<Object?> get props => [
        id,
        authorId,
        text,
        mediaItems,
        visibility,
        authorName,
        authorPhotoUrl,
        createdAt,
        updatedAt,
        likeCount,
        commentCount,
      ];
}
