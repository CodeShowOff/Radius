part of 'post_feed_bloc.dart';

/// Base class for post feed events.
abstract class PostFeedEvent extends Equatable {
  const PostFeedEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of the feed (first page).
class PostFeedLoadRequested extends PostFeedEvent {
  final String userId;
  final List<String> connectionIds;

  const PostFeedLoadRequested({
    required this.userId,
    required this.connectionIds,
  });

  @override
  List<Object?> get props => [userId, connectionIds];
}

/// Load more posts (next page).
class PostFeedLoadMore extends PostFeedEvent {
  const PostFeedLoadMore();
}

/// Pull-to-refresh the feed.
class PostFeedRefreshRequested extends PostFeedEvent {
  const PostFeedRefreshRequested();
}

/// Delete a post from the feed.
class PostFeedDeleteRequested extends PostFeedEvent {
  final String postId;

  const PostFeedDeleteRequested(this.postId);

  @override
  List<Object?> get props => [postId];
}

/// Change visibility of a post.
class PostFeedVisibilityChanged extends PostFeedEvent {
  final String postId;
  final PostVisibility newVisibility;
  final List<String> connectionIds;

  const PostFeedVisibilityChanged({
    required this.postId,
    required this.newVisibility,
    required this.connectionIds,
  });

  @override
  List<Object?> get props => [postId, newVisibility, connectionIds];
}
