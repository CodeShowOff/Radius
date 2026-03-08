import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/post.dart';
import '../../domain/repositories/i_post_repository.dart';

part 'user_posts_event.dart';
part 'user_posts_state.dart';

/// BLoC for loading a user's posts on their profile page.
///
/// Handles visibility filtering:
/// - Own profile: all posts
/// - Connected user: public + connections
/// - Non-connected user: public only
class UserPostsBloc extends Bloc<UserPostsEvent, UserPostsState> {
  final IPostRepository _postRepository;
  final Logger _logger;

  static const int _pageSize = 10;

  String? _userId;
  String? _viewerUserId;
  bool _isConnection = false;

  UserPostsBloc({
    required IPostRepository postRepository,
    Logger? logger,
  })  : _postRepository = postRepository,
        _logger = logger ?? Logger(),
        super(const UserPostsState()) {
    on<UserPostsLoadRequested>(_onLoadRequested);
    on<UserPostsLoadMore>(_onLoadMore);
    on<UserPostsRefreshRequested>(_onRefreshRequested);
    on<UserPostsDeleteRequested>(_onDeleteRequested);
    on<UserPostsVisibilityChanged>(_onVisibilityChanged);
  }

  Future<void> _onLoadRequested(
    UserPostsLoadRequested event,
    Emitter<UserPostsState> emit,
  ) async {
    _userId = event.userId;
    _viewerUserId = event.viewerUserId;
    _isConnection = event.isConnection;

    emit(state.copyWith(status: UserPostsStatus.loading));

    final result = await _postRepository.getUserPosts(
      userId: _userId!,
      viewerUserId: _viewerUserId!,
      isConnection: _isConnection,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load user posts: ${failure.message}');
        emit(state.copyWith(
          status: UserPostsStatus.error,
          errorMessage: failure.message,
        ));
      },
      (posts) {
        emit(state.copyWith(
          status: UserPostsStatus.loaded,
          posts: posts,
          hasMore: posts.length >= _pageSize,
        ));
      },
    );
  }

  Future<void> _onLoadMore(
    UserPostsLoadMore event,
    Emitter<UserPostsState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMore || _userId == null) return;

    emit(state.copyWith(isLoadingMore: true));

    final result = await _postRepository.getUserPosts(
      userId: _userId!,
      viewerUserId: _viewerUserId!,
      isConnection: _isConnection,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load more user posts: ${failure.message}');
        emit(state.copyWith(isLoadingMore: false));
      },
      (posts) {
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
    UserPostsRefreshRequested event,
    Emitter<UserPostsState> emit,
  ) async {
    if (_userId == null) return;

    final result = await _postRepository.getUserPosts(
      userId: _userId!,
      viewerUserId: _viewerUserId!,
      isConnection: _isConnection,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to refresh user posts: ${failure.message}');
      },
      (posts) {
        emit(state.copyWith(
          status: UserPostsStatus.loaded,
          posts: posts,
          hasMore: posts.length >= _pageSize,
        ));
      },
    );
  }

  Future<void> _onDeleteRequested(
    UserPostsDeleteRequested event,
    Emitter<UserPostsState> emit,
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
    UserPostsVisibilityChanged event,
    Emitter<UserPostsState> emit,
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
