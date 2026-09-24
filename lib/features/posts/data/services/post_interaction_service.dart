import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import '../models/comment_model.dart';
import '../models/post_like_model.dart';

/// Service for Firestore operations on post likes and comments.
///
/// Firestore Collections:
/// - `posts/{postId}/likes/{userId}` â€” One doc per like, keyed by userId
/// - `posts/{postId}/comments/{commentId}` â€” Auto-ID docs for comments
///
/// Counter fields on the post doc (`likeCount`, `commentCount`) are maintained
/// by Cloud Functions triggers for atomic consistency.
class PostInteractionService {
  final FirebaseFirestore _firestore;
  final Logger _logger;

  late final CollectionReference<Map<String, dynamic>> _postsRef;

  PostInteractionService({
    FirebaseFirestore? firestore,
    Logger? logger,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger() {
    _postsRef = _firestore.collection('posts');
  }

  // â”€â”€â”€ Likes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Toggles a like on a post. Returns `true` if liked, `false` if unliked.
  Future<bool> toggleLike({
    required String postId,
    required String userId,
    required String userName,
    String? userPhotoUrl,
  }) async {
    final likeRef = _postsRef.doc(postId).collection('likes').doc(userId);

    try {
      final doc = await likeRef.get();

      if (doc.exists) {
        // Unlike â€” remove the document
        await likeRef.delete();
        return false;
      } else {
        // Like â€” create the document
        final like = PostLikeModel(
          postId: postId,
          userId: userId,
          userName: userName,
          userPhotoUrl: userPhotoUrl,
          createdAt: DateTime.now(),
        );
        await likeRef.set(like.toFirestore());
        return true;
      }
    } catch (e, stack) {
      _logger.e('Error toggling like on post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Checks whether a specific user has liked a post.
  Future<bool> hasLiked({
    required String postId,
    required String userId,
  }) async {
    try {
      final doc =
          await _postsRef.doc(postId).collection('likes').doc(userId).get();
      return doc.exists;
    } catch (e, stack) {
      _logger.e('Error checking like on post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets the like count and isLiked status from the post document.
  Future<({int likeCount, int commentCount, bool isLiked})> getPostInteractionInfo({
    required String postId,
    required String userId,
  }) async {
    try {
      final results = await Future.wait([
        _postsRef.doc(postId).get(),
        _postsRef.doc(postId).collection('likes').doc(userId).get(),
      ]);

      final postDoc = results[0] as DocumentSnapshot;
      final likeDoc = results[1] as DocumentSnapshot;

      final data = postDoc.data() as Map<String, dynamic>? ?? {};
      return (
        likeCount: (data['likeCount'] as int?) ?? 0,
        commentCount: (data['commentCount'] as int?) ?? 0,
        isLiked: likeDoc.exists,
      );
    } catch (e, stack) {
      _logger.e('Error getting interaction info for post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Batch-fetches interaction info for multiple posts.
  Future<Map<String, ({int likeCount, int commentCount, bool isLiked})>>
      batchGetInteractionInfo({
    required List<String> postIds,
    required String userId,
  }) async {
    if (postIds.isEmpty) return {};

    try {
      final result =
          <String, ({int likeCount, int commentCount, bool isLiked})>{};

      // Process in batches of 10 to stay within Firestore limits
      const batchSize = 10;
      for (var i = 0; i < postIds.length; i += batchSize) {
        final batch = postIds.sublist(
          i,
          i + batchSize > postIds.length ? postIds.length : i + batchSize,
        );

        final futures = batch.map((postId) => getPostInteractionInfo(
              postId: postId,
              userId: userId,
            ));

        final infos = await Future.wait(futures);
        for (var j = 0; j < batch.length; j++) {
          result[batch[j]] = infos[j];
        }
      }

      return result;
    } catch (e, stack) {
      _logger.e('Error batch-getting interaction info',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  // â”€â”€â”€ Comments â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Adds a comment to a post. Returns the created comment.
  Future<CommentModel> addComment({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    required String text,
  }) async {
    try {
      final commentRef = _postsRef.doc(postId).collection('comments').doc();

      final comment = CommentModel(
        id: commentRef.id,
        postId: postId,
        authorId: authorId,
        authorName: authorName,
        authorPhotoUrl: authorPhotoUrl,
        text: text,
        createdAt: DateTime.now(),
      );

      await commentRef.set(comment.toFirestore());
      return comment;
    } catch (e, stack) {
      _logger.e('Error adding comment to post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Deletes a comment from a post.
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    try {
      await _postsRef
          .doc(postId)
          .collection('comments')
          .doc(commentId)
          .delete();
    } catch (e, stack) {
      _logger.e('Error deleting comment $commentId from post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets paginated comments for a post, ordered by creation time (newest first).
  Future<List<CommentModel>> getComments({
    required String postId,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _postsRef
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => CommentModel.fromFirestore(doc, postId))
          .toList();
    } catch (e, stack) {
      _logger.e('Error getting comments for post $postId',
          error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Streams real-time comment updates for a post.
  Stream<List<CommentModel>> commentsStream({
    required String postId,
    int limit = 50,
  }) {
    return _postsRef
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CommentModel.fromFirestore(doc, postId))
            .toList());
  }
}
