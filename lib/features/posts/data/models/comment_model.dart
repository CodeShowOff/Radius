import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/comment.dart';

/// Firestore model for post comments.
///
/// Firestore Schema:
/// ```
/// posts/{postId}/comments/{commentId}
///   - authorId: string
///   - authorName: string
///   - authorPhotoUrl: string?
///   - text: string (max 1000 chars)
///   - createdAt: timestamp
/// ```
class CommentModel extends Comment {
  const CommentModel({
    required super.id,
    required super.postId,
    required super.authorId,
    required super.authorName,
    super.authorPhotoUrl,
    required super.text,
    required super.createdAt,
  });

  factory CommentModel.fromFirestore(DocumentSnapshot doc, String postId) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw FormatException('Comment document ${doc.id} has no data');
    }

    return CommentModel(
      id: doc.id,
      postId: postId,
      authorId: data['authorId'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      authorPhotoUrl: data['authorPhotoUrl'] as String?,
      text: data['text'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory CommentModel.fromEntity(Comment comment) {
    return CommentModel(
      id: comment.id,
      postId: comment.postId,
      authorId: comment.authorId,
      authorName: comment.authorName,
      authorPhotoUrl: comment.authorPhotoUrl,
      text: comment.text,
      createdAt: comment.createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorName': _sanitizeField(authorName, 50),
      'authorPhotoUrl': authorPhotoUrl,
      'text': _sanitizeText(text),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  Comment toEntity() {
    return Comment(
      id: id,
      postId: postId,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      text: text,
      createdAt: createdAt,
    );
  }

  static const int maxTextLength = 1000;

  static String _sanitizeText(String value) {
    var sanitized =
        value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    sanitized = sanitized.trim();
    if (sanitized.length > maxTextLength) {
      sanitized = sanitized.substring(0, maxTextLength);
    }
    return sanitized;
  }

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
