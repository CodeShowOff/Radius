import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/post.dart';
import '../../domain/repositories/i_post_repository.dart';
import '../models/post_model.dart';
import '../services/post_service.dart';

/// Firestore-backed implementation of [IPostRepository].
class PostRepositoryImpl implements IPostRepository {
  final PostService _postService;

  PostRepositoryImpl({required PostService postService})
      : _postService = postService;

  @override
  Future<Either<Failure, Post>> createPost({
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    String? text,
    required List<Map<String, dynamic>> mediaItems,
    required PostVisibility visibility,
    required List<String> connectionIds,
  }) async {
    try {
      final now = DateTime.now();

      // Build media item entities from the raw maps
      final parsedMedia = mediaItems
          .map((m) => MediaItem(
                url: m['url'] as String,
                type: m['type'] as PostMediaType,
                thumbnailUrl: m['thumbnailUrl'] as String?,
                width: m['width'] as int?,
                height: m['height'] as int?,
                durationMs: m['durationMs'] as int?,
                storagePath: m['storagePath'] as String,
              ))
          .toList();

      final post = PostModel(
        id: '', // will be assigned by Firestore
        authorId: authorId,
        text: text,
        mediaItems: parsedMedia,
        visibility: visibility,
        authorName: authorName,
        authorPhotoUrl: authorPhotoUrl,
        createdAt: now,
        updatedAt: now,
        // Only populate authorConnections for connections-only posts
        authorConnections:
            visibility == PostVisibility.connections ? connectionIds : const [],
      );

      final created = await _postService.createPost(post);
      return Right(created.toEntity());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to create post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to create post: $e'));
    }
  }

  @override
  Future<Either<Failure, Post?>> getPost(String postId) async {
    try {
      final post = await _postService.getPost(postId);
      return Right(post?.toEntity());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get post: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deletePost(String postId) async {
    try {
      await _postService.deletePost(postId);
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to delete post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to delete post: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updatePostText(
      String postId, String? text) async {
    try {
      await _postService.updatePost(postId, {
        'text': text,
        'updatedAt': Timestamp.now(),
      });
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to update post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to update post: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updatePostVisibility({
    required String postId,
    required PostVisibility visibility,
    required List<String> connectionIds,
  }) async {
    try {
      await _postService.updatePost(postId, {
        'visibility': visibility.name,
        'authorConnections':
            visibility == PostVisibility.connections ? connectionIds : [],
        'updatedAt': Timestamp.now(),
      });
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to update post visibility',
        code: e.code,
      ));
    } catch (e) {
      return Left(
          DatabaseFailure(message: 'Failed to update post visibility: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Post>>> getUserPosts({
    required String userId,
    required String viewerUserId,
    required bool isConnection,
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      // Own profile or connected user → show all posts
      // Non-connected viewer → show public only
      final includeConnections = userId == viewerUserId || isConnection;

      final posts = await _postService.getPostsByAuthor(
        authorId: userId,
        includeConnectionsVisibility: includeConnections,
        viewerUserId: viewerUserId,
        limit: limit,
        startAfter: startAfter,
      );

      return Right(posts.map((p) => p.toEntity()).toList());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get user posts',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get user posts: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Post>>> getFeedPosts({
    required String userId,
    required List<String> connectionIds,
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      // Three parallel queries:
      // 1. User's own posts (all visibilities)
      // 2. Public posts from connections
      // 3. Connections-only posts visible to this user
      final futures = <Future<List<PostModel>>>[
        _postService.getPostsByAuthor(
          authorId: userId,
          includeConnectionsVisibility: true,
          viewerUserId: userId,
          limit: limit,
          startAfter: startAfter,
        ),
      ];

      if (connectionIds.isNotEmpty) {
        futures.add(_postService.getPublicPostsByAuthors(
          authorIds: connectionIds,
          limit: limit,
          startAfter: startAfter,
        ));
        futures.add(_postService.getConnectionsPostsForUser(
          userId: userId,
          limit: limit,
          startAfter: startAfter,
        ));
      }

      final results = await Future.wait(futures);

      // Merge and deduplicate
      final postMap = <String, PostModel>{};
      for (final batch in results) {
        for (final post in batch) {
          postMap[post.id] = post;
        }
      }

      // Sort by createdAt descending
      final merged = postMap.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Limit to requested page size
      final limited = merged.take(limit).toList();

      return Right(limited.map((p) => p.toEntity()).toList());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get feed posts',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get feed posts: $e'));
    }
  }

  @override
  Stream<Post?> postStream(String postId) {
    return _postService.postStream(postId).map((model) => model?.toEntity());
  }
}
