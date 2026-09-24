import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/post.dart';
import '../../domain/repositories/i_post_repository.dart';

part 'post_feed_event.dart';
part 'post_feed_state.dart';

/// BLoC for the post feed with paginated loading.
class PostFeedBloc extends Bloc<PostFeedEvent, PostFeedState> {
  final IPostRepository _postRepository;
  final Logger _logger;

  static const int _pageSize = 10;

  String? _userId;
  List<String> _connectionIds = const [];

  PostFeedBloc({
    required IPostRepository postRepository,
    Logger? logger,
  })  : _postRepository = postRepository,
        _logger = logger ?? Logger(),
        super(const PostFeedState()) {
    on<PostFeedLoadRequested>(_onLoadRequested);
    on<PostFeedLoadMore>(_onLoadMore);
    on<PostFeedRefreshRequested>(_onRefreshRequested);
    on<PostFeedDeleteRequested>(_onDeleteRequested);
    on<PostFeedVisibilityChanged>(_onVisibilityChanged);
  }

  Future<void> _onLoadRequested(
    PostFeedLoadRequested event,
    Emitter<PostFeedState> emit,
  ) async {
    _userId = event.userId;
    _connectionIds = event.connectionIds;

    emit(state.copyWith(status: PostFeedStatus.loading));

    final result = await _postRepository.getFeedPosts(
      userId: _userId!,
      connectionIds: _connectionIds,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load feed: ${failure.message}');
        emit(state.copyWith(
          status: PostFeedStatus.error,
          errorMessage: failure.message,
        ));
      },
      (posts) {
        emit(state.copyWith(
          status: PostFeedStatus.loaded,
          posts: posts,
          hasMore: posts.length >= _pageSize,
        ));
      },
    );
  }

  Future<void> _onLoadMore(
    PostFeedLoadMore event,
    Emitter<PostFeedState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMore || _userId == null) return;

    emit(state.copyWith(isLoadingMore: true));

    final result = await _postRepository.getFeedPosts(
      userId: _userId!,
      connectionIds: _connectionIds,
      limit: _pageSize,
      // Note: cursor-based pagination with startAfter requires
      // DocumentSnapshot which is not exposed through the domain layer.
      // For now we use offset-style by checking post count.
      // A proper cursor can be added by extending the repository.
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load more feed: ${failure.message}');
        emit(state.copyWith(isLoadingMore: false));
      },
      (posts) {
        // Deduplicate against existing posts
        final existingIds = state.posts.map((p) => p.id).toSet();
        final newPosts =
            posts.where((p) => !existingIds.contains(p.id)).toList();

        emit(state.copyWith(
          posts: [...state.posts, ...newPosts],
          hasMore: posts.length >= _pageSize,
          isLoadingMore: false,
        ));
      },
    );
  }

  Future<void> _onRefreshRequested(
    PostFeedRefreshRequested event,
    Emitter<PostFeedState> emit,
  ) async {
    if (_userId == null) return;

    // Don't show loading indicator â€” pull-to-refresh has its own
    final result = await _postRepository.getFeedPosts(
      userId: _userId!,
      connectionIds: _connectionIds,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to refresh feed: ${failure.message}');
        // Keep existing posts on refresh failure, but emit so UI knows refresh is done
        emit(state.copyWith(status: PostFeedStatus.loaded));
      },
      (posts) {
        emit(state.copyWith(
          status: PostFeedStatus.loaded,
          posts: posts,
          hasMore: posts.length >= _pageSize,
        ));
      },
    );

    event.completer?.complete();
  }

  Future<void> _onDeleteRequested(
    PostFeedDeleteRequested event,
    Emitter<PostFeedState> emit,
  ) async {
    final result = await _postRepository.deletePost(event.postId);

    result.fold(
      (failure) {
        _logger.e('Failed to delete post: ${failure.message}');
      },
      (_) {
        final updatedPosts =
            state.posts.where((p) => p.id != event.postId).toList();
        emit(state.copyWith(posts: updatedPosts));
      },
    );
  }

  Future<void> _onVisibilityChanged(
    PostFeedVisibilityChanged event,
    Emitter<PostFeedState> emit,
  ) async {
    final result = await _postRepository.updatePostVisibility(
      postId: event.postId,
      visibility: event.newVisibility,
      connectionIds: event.connectionIds,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to update visibility: ${failure.message}');
      },
      (_) {
        final updatedPosts = state.posts.map((p) {
          if (p.id == event.postId) {
            return p.copyWith(visibility: event.newVisibility);
          }
          return p;
        }).toList();
        emit(state.copyWith(posts: updatedPosts));
      },
    );
  }
}
