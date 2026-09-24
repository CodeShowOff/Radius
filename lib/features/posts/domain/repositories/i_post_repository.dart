import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/post.dart';

/// Abstract repository interface for post operations.
abstract class IPostRepository {
  /// Creates a new post.
  Future<Either<Failure, Post>> createPost({
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    String? text,
    required List<Map<String, dynamic>> mediaItems,
    required PostVisibility visibility,
    required List<String> connectionIds,
  });

  /// Gets a single post by ID.
  Future<Either<Failure, Post?>> getPost(String postId);

  /// Deletes a post.
  Future<Either<Failure, void>> deletePost(String postId);

  /// Updates a post's text/caption.
  Future<Either<Failure, void>> updatePostText(String postId, String? text);

  /// Updates a post's visibility setting.
  /// When changing to [PostVisibility.connections], [connectionIds] are stored
  /// so the post appears in connections' feeds.
  Future<Either<Failure, void>> updatePostVisibility({
    required String postId,
    required PostVisibility visibility,
    required List<String> connectionIds,
  });

  /// Gets posts by a specific user (for profile page).
  /// [viewerUserId] is the current viewer's ID for visibility filtering.
  /// [isConnection] whether the viewer is connected to the author.
  Future<Either<Failure, List<Post>>> getUserPosts({
    required String userId,
    required String viewerUserId,
    required bool isConnection,
    int limit = 10,
    DocumentSnapshot? startAfter,
  });

  /// Gets the feed posts for a user (posts from their connections).
  /// Returns public posts from connections + connections-only posts visible to the user.
  Future<Either<Failure, List<Post>>> getFeedPosts({
    required String userId,
    required List<String> connectionIds,
    int limit = 10,
    DocumentSnapshot? startAfter,
  });

  /// Streams real-time updates for a single post.
  Stream<Post?> postStream(String postId);
}
