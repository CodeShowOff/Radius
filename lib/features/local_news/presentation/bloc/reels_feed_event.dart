part of 'reels_feed_bloc.dart';

/// Base class for reels feed events.
abstract class ReelsFeedEvent extends Equatable {
  const ReelsFeedEvent();

  @override
  List<Object?> get props => [];
}

/// Load the reels feed for a specific location.
class ReelsFeedLoadRequested extends ReelsFeedEvent {
  final String country;
  final String city;

  const ReelsFeedLoadRequested({
    required this.country,
    required this.city,
  });

  @override
  List<Object?> get props => [country, city];
}

/// Load more reels (next page / pagination).
class ReelsFeedLoadMore extends ReelsFeedEvent {
  const ReelsFeedLoadMore();
}

/// Pull-to-refresh the reels feed.
class ReelsFeedRefreshRequested extends ReelsFeedEvent {
  const ReelsFeedRefreshRequested();
}

/// Delete a reel from the feed (optimistic removal).
class ReelsFeedReelDeleted extends ReelsFeedEvent {
  final String postId;

  const ReelsFeedReelDeleted(this.postId);

  @override
  List<Object?> get props => [postId];
}
