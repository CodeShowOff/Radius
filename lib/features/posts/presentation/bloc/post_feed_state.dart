part of 'post_feed_bloc.dart';

/// Status of the post feed.
enum PostFeedStatus {
  /// Feed has not been loaded yet.
  initial,

  /// Feed is loading for the first time.
  loading,

  /// Feed has been loaded successfully.
  loaded,

  /// An error occurred while loading the feed.
  error,
}

/// State for the post feed.
class PostFeedState extends Equatable {
  /// Current feed status.
  final PostFeedStatus status;

  /// Loaded posts.
  final List<Post> posts;

  /// Whether there are more posts to load.
  final bool hasMore;

  /// Whether a load-more operation is in progress.
  final bool isLoadingMore;

  /// Error message if status is error.
  final String? errorMessage;

  const PostFeedState({
    this.status = PostFeedStatus.initial,
    this.posts = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  PostFeedState copyWith({
    PostFeedStatus? status,
    List<Post>? posts,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
  }) {
    return PostFeedState(
      status: status ?? this.status,
      posts: posts ?? this.posts,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        posts,
        hasMore,
        isLoadingMore,
        errorMessage,
      ];
}
