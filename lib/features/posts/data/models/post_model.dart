import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/post.dart';
import 'media_item_model.dart';

/// Firestore model for Post entity.
///
/// Firestore Schema:
/// ```
/// posts/{postId}
///   - authorId: string
///   - text: string?
///   - mediaItems: list<map>
///   - visibility: string ('public', 'connections')
///   - authorName: string
///   - authorPhotoUrl: string?
///   - createdAt: timestamp
///   - updatedAt: timestamp
///   - authorConnections: list<string> (only for 'connections' visibility)
/// ```
class PostModel extends Post {
  /// Connection IDs for feed queries (only for 'connections' visibility posts).
  final List<String> authorConnections;

  const PostModel({
    required super.id,
    required super.authorId,
    super.text,
    super.mediaItems,
    required super.visibility,
    required super.authorName,
    super.authorPhotoUrl,
    required super.createdAt,
    required super.updatedAt,
    super.likeCount,
    super.commentCount,
    this.authorConnections = const [],
  });

  /// Creates model from Firestore document.
  /// Throws [FormatException] if required fields are missing.
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      throw FormatException('Post document ${doc.id} has no data');
    }

    final authorId = data['authorId'] as String?;
    final createdAt = data['createdAt'] as Timestamp?;
    final updatedAt = data['updatedAt'] as Timestamp?;

    if (authorId == null || createdAt == null || updatedAt == null) {
      throw FormatException(
        'Post document ${doc.id} missing required fields: '
        'authorId=$authorId, createdAt=$createdAt, updatedAt=$updatedAt',
      );
    }

    // Parse media items
    final rawMediaItems = data['mediaItems'] as List<dynamic>? ?? [];
    final mediaItems = rawMediaItems
        .map((item) => MediaItemModel.fromMap(item as Map<String, dynamic>).toEntity())
        .toList();

    // Parse author connections
    final rawConnections = data['authorConnections'] as List<dynamic>? ?? [];
    final authorConnections =
        rawConnections.map((e) => e as String).toList();

    return PostModel(
      id: doc.id,
      authorId: authorId,
      text: data['text'] as String?,
      mediaItems: mediaItems,
      visibility: _parseVisibility(data['visibility'] as String? ?? 'public'),
      authorName: data['authorName'] as String? ?? '',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      createdAt: createdAt.toDate(),
      updatedAt: updatedAt.toDate(),
      likeCount: (data['likeCount'] as int?) ?? 0,
      commentCount: (data['commentCount'] as int?) ?? 0,
      authorConnections: authorConnections,
    );
  }

  /// Creates model from domain entity.
  factory PostModel.fromEntity(Post post, {List<String> authorConnections = const []}) {
    return PostModel(
      id: post.id,
      authorId: post.authorId,
      text: post.text,
      mediaItems: post.mediaItems,
      visibility: post.visibility,
      authorName: post.authorName,
      authorPhotoUrl: post.authorPhotoUrl,
      createdAt: post.createdAt,
      updatedAt: post.updatedAt,
      likeCount: post.likeCount,
      commentCount: post.commentCount,
      authorConnections: authorConnections,
    );
  }

  /// Converts to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'text': text != null ? _sanitizeText(text!) : null,
      'mediaItems':
          mediaItems.map((item) => MediaItemModel.fromEntity(item).toMap()).toList(),
      'visibility': visibility.name,
      'authorName': _sanitizeField(authorName, maxNameLength),
      'authorPhotoUrl': authorPhotoUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'authorConnections': authorConnections,
    };
  }

  /// Converts to domain entity.
  Post toEntity() {
    return Post(
      id: id,
      authorId: authorId,
      text: text,
      mediaItems: mediaItems,
      visibility: visibility,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      createdAt: createdAt,
      updatedAt: updatedAt,
      likeCount: likeCount,
      commentCount: commentCount,
    );
  }

  static PostVisibility _parseVisibility(String visibility) {
    return PostVisibility.values.firstWhere(
      (e) => e.name == visibility,
      orElse: () => PostVisibility.public,
    );
  }

  /// Maximum allowed lengths.
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
}
