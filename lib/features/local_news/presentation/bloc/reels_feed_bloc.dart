import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_post_repository.dart';

part 'reels_feed_event.dart';
part 'reels_feed_state.dart';

/// BLoC for the local news reels feed with paginated loading.
///
/// Queries posts with `postType == 'reel'` by country + city,
/// supports infinite-scroll pagination and pull-to-refresh.
class ReelsFeedBloc extends Bloc<ReelsFeedEvent, ReelsFeedState> {
  final INewsPostRepository _repository;
  final Logger _logger;

  static const int _pageSize = 10;

  String? _country;
  String? _city;

  ReelsFeedBloc({
    required INewsPostRepository repository,
    Logger? logger,
  })  : _repository = repository,
        _logger = logger ?? Logger(),
        super(const ReelsFeedState()) {
    on<ReelsFeedLoadRequested>(_onLoadRequested);
    on<ReelsFeedLoadMore>(_onLoadMore);
    on<ReelsFeedRefreshRequested>(_onRefreshRequested);
    on<ReelsFeedReelDeleted>(_onReelDeleted);
  }

  Future<void> _onLoadRequested(
    ReelsFeedLoadRequested event,
    Emitter<ReelsFeedState> emit,
  ) async {
    _country = event.country;
    _city = event.city;

    emit(state.copyWith(
      status: ReelsFeedStatus.loading,
      country: event.country,
      city: event.city,
      currentIndex: 0,
    ));

    final result = await _repository.getReelsFeed(
      country: event.country,
      city: event.city,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load reels feed: ${failure.message}');
        emit(state.copyWith(
          status: ReelsFeedStatus.error,
          errorMessage: failure.message,
        ));
      },
      (reels) {
        emit(state.copyWith(
          status: ReelsFeedStatus.loaded,
          reels: reels,
          hasMore: reels.length >= _pageSize,
          currentIndex: 0,
        ));
      },
    );
  }

  Future<void> _onLoadMore(
    ReelsFeedLoadMore event,
    Emitter<ReelsFeedState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMore) return;
    if (_country == null || _city == null) return;

    emit(state.copyWith(isLoadingMore: true));

    final result = await _repository.getReelsFeed(
      country: _country!,
      city: _city!,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to load more reels: ${failure.message}');
        emit(state.copyWith(isLoadingMore: false));
      },
      (reels) {
        // Deduplicate against existing reels
        final existingIds = state.reels.map((r) => r.id).toSet();
        final newReels =
            reels.where((r) => !existingIds.contains(r.id)).toList();

        emit(state.copyWith(
          reels: [...state.reels, ...newReels],
          hasMore: reels.length >= _pageSize,
          isLoadingMore: false,
        ));
      },
    );
  }

  Future<void> _onRefreshRequested(
    ReelsFeedRefreshRequested event,
    Emitter<ReelsFeedState> emit,
  ) async {
    if (_country == null || _city == null) return;

    final result = await _repository.getReelsFeed(
      country: _country!,
      city: _city!,
      limit: _pageSize,
    );

    result.fold(
      (failure) {
        _logger.e('Failed to refresh reels feed: ${failure.message}');
        // Keep existing reels on refresh failure
        emit(state.copyWith(status: ReelsFeedStatus.loaded));
      },
      (reels) {
        emit(state.copyWith(
          status: ReelsFeedStatus.loaded,
          reels: reels,
          hasMore: reels.length >= _pageSize,
          currentIndex: 0,
        ));
      },
    );
  }

  Future<void> _onReelDeleted(
    ReelsFeedReelDeleted event,
    Emitter<ReelsFeedState> emit,
  ) async {
    // Optimistic removal from local state
    final updatedReels =
        state.reels.where((r) => r.id != event.postId).toList();

    // Adjust currentIndex if needed
    final newIndex = state.currentIndex >= updatedReels.length
        ? (updatedReels.isEmpty ? 0 : updatedReels.length - 1)
        : state.currentIndex;

    emit(state.copyWith(reels: updatedReels, currentIndex: newIndex));

    // Persist deletion
    final result = await _repository.deletePost(event.postId);

    result.fold(
      (failure) {
        _logger.e('Failed to delete reel: ${failure.message}');
        // Restore on failure â€” re-fetch
        if (_country != null && _city != null) {
          add(const ReelsFeedRefreshRequested());
        }
      },
      (_) {
        // Deletion succeeded
      },
    );
  }
}
