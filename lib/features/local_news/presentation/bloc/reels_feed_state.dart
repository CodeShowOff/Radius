part of 'reels_feed_bloc.dart';

/// Status of the reels feed.
enum ReelsFeedStatus {
  /// Feed has not been loaded yet.
  initial,

  /// Feed is loading for the first time.
  loading,

  /// Feed has been loaded successfully.
  loaded,

  /// An error occurred while loading the feed.
  error,
}

/// State for the local news reels feed.
class ReelsFeedState extends Equatable {
  /// Current feed status.
  final ReelsFeedStatus status;

  /// Loaded reels (NewsPost with postType == 'reel').
  final List<NewsPost> reels;

  /// Whether there are more reels to load.
  final bool hasMore;

  /// Whether a load-more operation is in progress.
  final bool isLoadingMore;

  /// Error message if status is error.
  final String? errorMessage;

  /// Country the feed is scoped to.
  final String? country;

  /// District the feed is scoped to.
  final String? district;

  /// Index of the currently active/visible reel.
  final int currentIndex;

  const ReelsFeedState({
    this.status = ReelsFeedStatus.initial,
    this.reels = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.errorMessage,
    this.country,
    this.district,
    this.currentIndex = 0,
  });

  ReelsFeedState copyWith({
    ReelsFeedStatus? status,
    List<NewsPost>? reels,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
    String? country,
    String? district,
    int? currentIndex,
  }) {
    return ReelsFeedState(
      status: status ?? this.status,
      reels: reels ?? this.reels,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
      country: country ?? this.country,
      district: district ?? this.district,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  @override
  List<Object?> get props => [
        status,
        reels,
        hasMore,
        isLoadingMore,
        errorMessage,
        country,
        district,
        currentIndex,
      ];
}
