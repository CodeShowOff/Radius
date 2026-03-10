part of 'news_feed_bloc.dart';

/// Base class for news feed events.
abstract class NewsFeedEvent extends Equatable {
  const NewsFeedEvent();

  @override
  List<Object?> get props => [];
}

/// Load the news feed for a specific location.
class NewsFeedLoadRequested extends NewsFeedEvent {
  final String country;
  final String city;

  const NewsFeedLoadRequested({
    required this.country,
    required this.city,
  });

  @override
  List<Object?> get props => [country, city];
}

/// Load more posts (next page / pagination).
class NewsFeedLoadMore extends NewsFeedEvent {
  const NewsFeedLoadMore();
}

/// Pull-to-refresh the feed.
class NewsFeedRefreshRequested extends NewsFeedEvent {
  const NewsFeedRefreshRequested();
}

/// Delete a post from the feed (optimistic removal).
class NewsFeedPostDeleted extends NewsFeedEvent {
  final String postId;

  const NewsFeedPostDeleted(this.postId);

  @override
  List<Object?> get props => [postId];
}
