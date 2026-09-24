import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/news_post.dart';

/// Abstract repository interface for local news post operations.
abstract class INewsPostRepository {
  /// Creates a new local news post.
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
  });

  /// Gets a single post by ID.
  Future<Either<Failure, NewsPost?>> getPost(String postId);

  /// Deletes a post.
  Future<Either<Failure, void>> deletePost(String postId);

  /// Updates a post's text content.
  Future<Either<Failure, void>> updatePostText(String postId, String? text);

  /// Gets the news feed for a specific location (city + country).
  Future<Either<Failure, List<NewsPost>>> getNewsFeed({
    required String country,
    required String city,
    int limit = 20,
    DocumentSnapshot? startAfter,
  });

  /// Watches the real-time news feed for a location.
  Stream<List<NewsPost>> watchNewsFeed({
    required String country,
    required String city,
    int limit = 20,
  });

  /// Gets posts by a specific author.
  Future<Either<Failure, List<NewsPost>>> getPostsByAuthor({
    required String authorId,
    int limit = 20,
    DocumentSnapshot? startAfter,
  });

  /// Streams real-time updates for a single post.
  Stream<NewsPost?> postStream(String postId);

  /// Gets the reels feed for a specific location (city + country).
  Future<Either<Failure, List<NewsPost>>> getReelsFeed({
    required String country,
    required String city,
    int limit = 10,
    DocumentSnapshot? startAfter,
  });

  /// Watches the real-time reels feed for a location.
  Stream<List<NewsPost>> watchReelsFeed({
    required String country,
    required String city,
    int limit = 10,
  });
}
