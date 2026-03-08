import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_post_repository.dart';
import '../models/news_post_model.dart';
import '../services/news_post_service.dart';

/// Firestore-backed implementation of [INewsPostRepository].
class NewsPostRepositoryImpl implements INewsPostRepository {
  final NewsPostService _postService;

  NewsPostRepositoryImpl({required NewsPostService postService})
      : _postService = postService;

  @override
  Future<Either<Failure, NewsPost>> createPost({
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    String? text,
    required List<Map<String, dynamic>> mediaItems,
    required double latitude,
    required double longitude,
    required String district,
    required String city,
    required String locality,
    required String country,
    String postType = 'post',
  }) async {
    try {
      final now = DateTime.now();

      final parsedMedia = mediaItems
          .map((m) => MediaItem(
                url: m['url'] as String,
                type: m['type'] is PostMediaType
                    ? m['type'] as PostMediaType
                    : PostMediaType.values.firstWhere(
                        (e) => e.name == m['type'],
                        orElse: () => PostMediaType.image,
                      ),
                thumbnailUrl: m['thumbnailUrl'] as String?,
                width: m['width'] as int?,
                height: m['height'] as int?,
                durationMs: m['durationMs'] as int?,
                storagePath: m['storagePath'] as String,
              ))
          .toList();

      final geoHash = NewsPostModel.generateGeoHash(latitude, longitude);

      final post = NewsPostModel(
        id: '', // will be assigned by Firestore
        authorId: authorId,
        text: text,
        mediaItems: parsedMedia,
        authorName: authorName,
        authorPhotoUrl: authorPhotoUrl,
        latitude: latitude,
        longitude: longitude,
        geoHash: geoHash,
        district: district,
        city: city,
        locality: locality,
        country: country,
        createdAt: now,
        updatedAt: now,
        postType: postType,
      );

      final created = await _postService.createPost(post);
      return Right(created.toEntity());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to create news post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to create news post: $e'));
    }
  }

  @override
  Future<Either<Failure, NewsPost?>> getPost(String postId) async {
    try {
      final post = await _postService.getPost(postId);
      return Right(post?.toEntity());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get news post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get news post: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deletePost(String postId) async {
    try {
      await _postService.deletePost(postId);
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to delete news post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to delete news post: $e'));
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
        message: e.message ?? 'Failed to update news post',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to update news post: $e'));
    }
  }

  @override
  Future<Either<Failure, List<NewsPost>>> getNewsFeed({
    required String country,
    required String district,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final posts = await _postService.getNewsFeed(
        country: country,
        district: district,
        limit: limit,
        startAfter: startAfter,
      );
      return Right(posts.map((p) => p.toEntity()).toList());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get news feed',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get news feed: $e'));
    }
  }

  @override
  Stream<List<NewsPost>> watchNewsFeed({
    required String country,
    required String district,
    int limit = 20,
  }) {
    return _postService
        .watchNewsFeed(country: country, district: district, limit: limit)
        .map((models) => models.map((m) => m.toEntity()).toList());
  }

  @override
  Future<Either<Failure, List<NewsPost>>> getPostsByAuthor({
    required String authorId,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final posts = await _postService.getPostsByAuthor(
        authorId: authorId,
        limit: limit,
        startAfter: startAfter,
      );
      return Right(posts.map((p) => p.toEntity()).toList());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get author news posts',
        code: e.code,
      ));
    } catch (e) {
      return Left(
          DatabaseFailure(message: 'Failed to get author news posts: $e'));
    }
  }

  @override
  Stream<NewsPost?> postStream(String postId) {
    return _postService.postStream(postId).map((model) => model?.toEntity());
  }

  @override
  Future<Either<Failure, List<NewsPost>>> getReelsFeed({
    required String country,
    required String district,
    int limit = 10,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final reels = await _postService.getReelsFeed(
        country: country,
        district: district,
        limit: limit,
        startAfter: startAfter,
      );
      return Right(reels.map((r) => r.toEntity()).toList());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get reels feed',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get reels feed: $e'));
    }
  }

  @override
  Stream<List<NewsPost>> watchReelsFeed({
    required String country,
    required String district,
    int limit = 10,
  }) {
    return _postService
        .watchReelsFeed(country: country, district: district, limit: limit)
        .map((models) => models.map((m) => m.toEntity()).toList());
  }
}
