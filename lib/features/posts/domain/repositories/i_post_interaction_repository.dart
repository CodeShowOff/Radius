import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/comment.dart';

/// Abstract repository interface for post interaction operations (likes & comments).
abstract class IPostInteractionRepository {
  /// Toggles a like on a post. Returns `true` if now liked, `false` if unliked.
  Future<Either<Failure, bool>> toggleLike({
    required String postId,
    required String userId,
    required String userName,
    String? userPhotoUrl,
  });

  /// Gets interaction info (like count, comment count, isLiked) for a post.
  Future<Either<Failure, ({int likeCount, int commentCount, bool isLiked})>>
      getPostInteractionInfo({
    required String postId,
    required String userId,
  });

  /// Batch-fetches interaction info for multiple posts.
  Future<
          Either<Failure,
              Map<String, ({int likeCount, int commentCount, bool isLiked})>>>
      batchGetInteractionInfo({
    required List<String> postIds,
    required String userId,
  });

  /// Adds a comment to a post.
  Future<Either<Failure, Comment>> addComment({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    required String text,
  });

  /// Deletes a comment from a post.
  Future<Either<Failure, void>> deleteComment({
    required String postId,
    required String commentId,
  });

  /// Gets paginated comments for a post.
  Future<Either<Failure, List<Comment>>> getComments({
    required String postId,
    int limit = 20,
  });

  /// Streams real-time comments for a post.
  Stream<List<Comment>> commentsStream({
    required String postId,
    int limit = 50,
  });
}
