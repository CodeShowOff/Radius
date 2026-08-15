import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../../posts/domain/entities/comment.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';

part 'news_interaction_state.dart';

/// Cubit managing per-news-post interaction state (likes & comments).
///
/// One instance per news post card — lightweight, focused on a single post.
class NewsInteractionCubit extends Cubit<NewsInteractionState> {
  final INewsInteractionRepository _repository;
  final Logger _logger;

  NewsInteractionCubit({
    required INewsInteractionRepository repository,
    Logger? logger,
  })  : _repository = repository,
        _logger = logger ?? Logger(),
        super(const NewsInteractionState());

  /// Loads interaction info (like count, comment count, isLiked) for a post.
  Future<void> loadInteractionInfo({
    required String postId,
    required String userId,
    int initialLikeCount = 0,
    int initialCommentCount = 0,
  }) async {
    emit(state.copyWith(
      postId: postId,
      userId: userId,
      likeCount: initialLikeCount,
      commentCount: initialCommentCount,
    ));

    final result = await _repository.getPostInteractionInfo(
      postId: postId,
      userId: userId,
    );

    result.fold(
      (failure) {
        _logger.w('Failed to load news interaction info: ${failure.message}');
      },
      (info) {
        if (!isClosed) {
          emit(state.copyWith(
            likeCount: info.likeCount,
            commentCount: info.commentCount,
            isLiked: info.isLiked,
            isLoaded: true,
          ));
        }
      },
    );
  }

  /// Toggles the like state with optimistic update.
  Future<void> toggleLike({
    required String userName,
    String? userPhotoUrl,
  }) async {
    if (state.postId == null || state.userId == null) return;
    if (state.isLikeInProgress) return;

    // Optimistic update
    final wasLiked = state.isLiked;
    final previousCount = state.likeCount;
    emit(state.copyWith(
      isLiked: !wasLiked,
      likeCount: wasLiked ? previousCount - 1 : previousCount + 1,
      isLikeInProgress: true,
    ));

    final result = await _repository.toggleLike(
      postId: state.postId!,
      userId: state.userId!,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to toggle news like: ${failure.message}');
        // Revert optimistic update
        if (!isClosed) {
          emit(state.copyWith(
            isLiked: wasLiked,
            likeCount: previousCount,
            isLikeInProgress: false,
          ));
        }
      },
      (isLikedResult) {
        // Record engagement
        _repository.recordEngagement(
          postId: state.postId!,
          userId: state.userId!,
          score: isLikedResult ? 5 : -5, // +5 for like, -5 for unlike
          actionType: isLikedResult ? 'like' : 'unlike',
        );

        if (!isClosed) {
          emit(state.copyWith(isLikeInProgress: false));
        }
      },
    );
  }

  /// Loads comments for the post.
  Future<void> loadComments() async {
    if (state.postId == null) return;
    if (state.isLoadingComments) return;

    emit(state.copyWith(isLoadingComments: true));

    final result = await _repository.getComments(
      postId: state.postId!,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load news comments: ${failure.message}');
        if (!isClosed) {
          emit(state.copyWith(isLoadingComments: false));
        }
      },
      (comments) {
        if (!isClosed) {
          emit(state.copyWith(
            comments: comments,
            isLoadingComments: false,
          ));
        }
      },
    );
  }

  /// Adds a new comment with optimistic insertion.
  Future<void> addComment({
    required String authorName,
    String? authorPhotoUrl,
    required String text,
  }) async {
    if (state.postId == null || state.userId == null) return;
    if (state.isSubmittingComment) return;

    emit(state.copyWith(isSubmittingComment: true));

    final result = await _repository.addComment(
      postId: state.postId!,
      authorId: state.userId!,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      text: text,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to add news comment: ${failure.message}');
        if (!isClosed) {
          emit(state.copyWith(isSubmittingComment: false));
        }
      },
      (comment) {
        // Record engagement
        _repository.recordEngagement(
          postId: state.postId!,
          userId: state.userId!,
          score: 10, // +10 points for comment
          actionType: 'comment',
        );

        if (!isClosed) {
          emit(state.copyWith(
            comments: [comment, ...state.comments],
            commentCount: state.commentCount + 1,
            isSubmittingComment: false,
          ));
        }
      },
    );
  }

  /// Deletes a comment with optimistic removal.
  Future<void> deleteComment(String commentId) async {
    if (state.postId == null) return;

    final previousComments = state.comments;
    final updatedComments =
        state.comments.where((c) => c.id != commentId).toList();

    // Optimistic removal
    emit(state.copyWith(
      comments: updatedComments,
      commentCount: state.commentCount - 1,
    ));

    final result = await _repository.deleteComment(
      postId: state.postId!,
      commentId: commentId,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to delete news comment: ${failure.message}');
        // Revert
        if (!isClosed) {
          emit(state.copyWith(
            comments: previousComments,
            commentCount: state.commentCount + 1,
          ));
        }
      },
      (_) {},
    );
  }

  /// Records a share action engagement.
  void recordShare() {
    if (state.postId == null || state.userId == null) return;
    _repository.recordEngagement(
      postId: state.postId!,
      userId: state.userId!,
      score: 20, // +20 points for share
      actionType: 'share',
    );
  }

  /// Records watch time engagement.
  void recordWatchTime({required int watchedMs, required int totalMs}) {
    if (state.postId == null || state.userId == null) return;
    
    // Evaluate score based on rules
    int score = 0;
    if (watchedMs < 1000) {
      score = -5; // Swiped away in less than 1 second
    } else if (watchedMs >= totalMs && totalMs > 0) {
      score = 10; // Watched 100%
    } else {
      score = 1; // Base score for partial watch
    }

    _repository.recordEngagement(
      postId: state.postId!,
      userId: state.userId!,
      score: score,
      actionType: 'watch',
    );
  }
}
