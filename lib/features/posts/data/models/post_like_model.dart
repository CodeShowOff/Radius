import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/post_like.dart';

/// Firestore model for post likes.
///
/// Firestore Schema:
/// ```
/// posts/{postId}/likes/{userId}
///   - userId: string
///   - userName: string
///   - userPhotoUrl: string?
///   - createdAt: timestamp
/// ```
class PostLikeModel extends PostLike {
  const PostLikeModel({
    required super.postId,
    required super.userId,
    required super.userName,
    super.userPhotoUrl,
    required super.createdAt,
  });

  factory PostLikeModel.fromFirestore(DocumentSnapshot doc, String postId) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw FormatException('Like document ${doc.id} has no data');
    }

    return PostLikeModel(
      postId: postId,
      userId: doc.id,
      userName: data['userName'] as String? ?? '',
      userPhotoUrl: data['userPhotoUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory PostLikeModel.fromEntity(PostLike like) {
    return PostLikeModel(
      postId: like.postId,
      userId: like.userId,
      userName: like.userName,
      userPhotoUrl: like.userPhotoUrl,
      createdAt: like.createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'userName': _sanitizeField(userName, 50),
      'userPhotoUrl': userPhotoUrl,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  PostLike toEntity() {
    return PostLike(
      postId: postId,
      userId: userId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      createdAt: createdAt,
    );
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
