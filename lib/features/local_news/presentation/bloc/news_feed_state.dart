part of 'news_feed_bloc.dart';

/// Status of the news feed.
enum NewsFeedStatus {
  /// Feed has not been loaded yet.
  initial,

  /// Feed is loading for the first time.
  loading,

  /// Feed has been loaded successfully.
  loaded,

  /// An error occurred while loading the feed.
  error,
}

/// State for the local news feed.
class NewsFeedState extends Equatable {
  /// Current feed status.
  final NewsFeedStatus status;

  /// Loaded news posts.
  final List<NewsPost> posts;

  /// Whether there are more posts to load.
  final bool hasMore;

  /// Whether a load-more operation is in progress.
  final bool isLoadingMore;

  /// Error message if status is error.
  final String? errorMessage;

  /// Country the feed is scoped to.
  final String? country;

  /// City the feed is scoped to.
  final String? city;

  const NewsFeedState({
    this.status = NewsFeedStatus.initial,
    this.posts = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.errorMessage,
    this.country,
    this.city,
  });

  /// Location label for the feed header.
  String get locationLabel {
    if (city != null && country != null) {
      return '$city, $country';
    }
    return '';
  }

  NewsFeedState copyWith({
    NewsFeedStatus? status,
    List<NewsPost>? posts,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
    String? country,
    String? city,
  }) {
    return NewsFeedState(
      status: status ?? this.status,
      posts: posts ?? this.posts,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
      country: country ?? this.country,
      city: city ?? this.city,
    );
  }

  @override
  List<Object?> get props => [
        status,
        posts,
        hasMore,
        isLoadingMore,
        errorMessage,
        country,
        city,
      ];
}
