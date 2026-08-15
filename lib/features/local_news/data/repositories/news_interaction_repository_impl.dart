import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../../posts/domain/entities/comment.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../services/news_interaction_service.dart';

/// Firestore-backed implementation of [INewsInteractionRepository].
class NewsInteractionRepositoryImpl implements INewsInteractionRepository {
  final NewsInteractionService _service;

  NewsInteractionRepositoryImpl({required NewsInteractionService service})
      : _service = service;

  @override
  Future<Either<Failure, bool>> toggleLike({
    required String postId,
    required String userId,
    required String userName,
    String? userPhotoUrl,
  }) async {
    try {
      final isLiked = await _service.toggleLike(
        postId: postId,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
      );
      return Right(isLiked);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to toggle like',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to toggle like: $e'));
    }
  }

  @override
  Future<Either<Failure, ({int likeCount, int commentCount, bool isLiked})>>
      getPostInteractionInfo({
    required String postId,
    required String userId,
  }) async {
    try {
      final info = await _service.getPostInteractionInfo(
        postId: postId,
        userId: userId,
      );
      return Right(info);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get interaction info',
        code: e.code,
      ));
    } catch (e) {
      return Left(
          DatabaseFailure(message: 'Failed to get interaction info: $e'));
    }
  }

  @override
  Future<
          Either<Failure,
              Map<String, ({int likeCount, int commentCount, bool isLiked})>>>
      batchGetInteractionInfo({
    required List<String> postIds,
    required String userId,
  }) async {
    try {
      final result = await _service.batchGetInteractionInfo(
        postIds: postIds,
        userId: userId,
      );
      return Right(result);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to batch-get interaction info',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(
          message: 'Failed to batch-get interaction info: $e'));
    }
  }

  @override
  Future<Either<Failure, Comment>> addComment({
    required String postId,
    required String authorId,
    required String authorName,
    String? authorPhotoUrl,
    required String text,
  }) async {
    try {
      final comment = await _service.addComment(
        postId: postId,
        authorId: authorId,
        authorName: authorName,
        authorPhotoUrl: authorPhotoUrl,
        text: text,
      );
      return Right(comment.toEntity());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to add comment',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to add comment: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    try {
      await _service.deleteComment(postId: postId, commentId: commentId);
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to delete comment',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to delete comment: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Comment>>> getComments({
    required String postId,
    int limit = 20,
  }) async {
    try {
      final comments = await _service.getComments(
        postId: postId,
        limit: limit,
      );
      return Right(comments.map((c) => c.toEntity()).toList());
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to get comments',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to get comments: $e'));
    }
  }

  @override
  Stream<List<Comment>> commentsStream({
    required String postId,
    int limit = 50,
  }) {
    return _service
        .commentsStream(postId: postId, limit: limit)
        .map((models) => models.map((m) => m.toEntity()).toList());
  }

  @override
  Future<Either<Failure, void>> recordEngagement({
    required String postId,
    required String userId,
    required int score,
    required String actionType,
  }) async {
    try {
      await _service.recordEngagement(
        postId: postId,
        userId: userId,
        score: score,
        actionType: actionType,
      );
      return const Right(null);
    } on FirebaseException catch (e) {
      return Left(DatabaseFailure(
        message: e.message ?? 'Failed to record engagement',
        code: e.code,
      ));
    } catch (e) {
      return Left(DatabaseFailure(message: 'Failed to record engagement: $e'));
    }
  }
}
