import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_post_repository.dart';

part 'news_feed_event.dart';
part 'news_feed_state.dart';

/// BLoC for the local news feed with paginated loading.
///
/// Queries posts by country + district, supports infinite-scroll pagination
/// and pull-to-refresh.
class NewsFeedBloc extends Bloc<NewsFeedEvent, NewsFeedState> {
  final INewsPostRepository _repository;
  final Logger _logger;

  static const int _pageSize = 20;

  String? _country;
  String? _district;

  NewsFeedBloc({
    required INewsPostRepository repository,
    Logger? logger,
  })  : _repository = repository,
        _logger = logger ?? Logger(),
        super(const NewsFeedState()) {
    on<NewsFeedLoadRequested>(_onLoadRequested);
    on<NewsFeedLoadMore>(_onLoadMore);
    on<NewsFeedRefreshRequested>(_onRefreshRequested);
    on<NewsFeedPostDeleted>(_onPostDeleted);
  }

  Future<void> _onLoadRequested(
    NewsFeedLoadRequested event,
    Emitter<NewsFeedState> emit,
  ) async {
    _country = event.country;
    _district = event.district;

    emit(state.copyWith(
      status: NewsFeedStatus.loading,
      country: event.country,
      district: event.district,
    ));

    final result = await _repository.getNewsFeed(
      country: event.country,
      district: event.district,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load news feed: ${failure.message}');
        emit(state.copyWith(
          status: NewsFeedStatus.error,
          errorMessage: failure.message,
        ));
      },
      (posts) {
        emit(state.copyWith(
          status: NewsFeedStatus.loaded,
          posts: posts,
          hasMore: posts.length >= _pageSize,
        ));
      },
    );
  }

  Future<void> _onLoadMore(
    NewsFeedLoadMore event,
    Emitter<NewsFeedState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMore) return;
    if (_country == null || _district == null) return;

    emit(state.copyWith(isLoadingMore: true));

    final result = await _repository.getNewsFeed(
      country: _country!,
      district: _district!,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load more news: ${failure.message}');
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
    NewsFeedRefreshRequested event,
    Emitter<NewsFeedState> emit,
  ) async {
    if (_country == null || _district == null) return;

    // Don't show loading indicator — pull-to-refresh has its own
    final result = await _repository.getNewsFeed(
      country: _country!,
      district: _district!,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to refresh news feed: ${failure.message}');
        // Keep existing posts on refresh failure
        emit(state.copyWith(status: NewsFeedStatus.loaded));
      },
      (posts) {
        emit(state.copyWith(
          status: NewsFeedStatus.loaded,
          posts: posts,
          hasMore: posts.length >= _pageSize,
        ));
      },
    );
  }

  Future<void> _onPostDeleted(
    NewsFeedPostDeleted event,
    Emitter<NewsFeedState> emit,
  ) async {
    // Optimistic removal from local state
    final updatedPosts =
        state.posts.where((p) => p.id != event.postId).toList();
    emit(state.copyWith(posts: updatedPosts));

    // Persist deletion
    final result = await _repository.deletePost(event.postId);

    result.fold(
      (failure) {
        _logger.e('Failed to delete news post: ${failure.message}');
        // Restore the post on failure — re-fetch
        if (_country != null && _district != null) {
          add(NewsFeedRefreshRequested());
        }
      },
      (_) {
        // Deletion succeeded — nothing more to do
      },
    );
  }
}
