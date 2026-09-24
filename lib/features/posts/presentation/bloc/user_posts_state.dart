part of 'user_posts_bloc.dart';

/// Status of user posts loading.
enum UserPostsStatus {
  /// Not loaded yet.
  initial,

  /// Loading for the first time.
  loading,

  /// Successfully loaded.
  loaded,

  /// An error occurred.
  error,
}

/// State for user posts on a profile page.
class UserPostsState extends Equatable {
  /// Current status.
  final UserPostsStatus status;

  /// Loaded posts.
  final List<Post> posts;

  /// Whether there are more posts to load.
  final bool hasMore;

  /// Whether a load-more operation is in progress.
  final bool isLoadingMore;

  /// Error message if status is error.
  final String? errorMessage;

  const UserPostsState({
    this.status = UserPostsStatus.initial,
    this.posts = const [],
    this.hasMore = true,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  UserPostsState copyWith({
    UserPostsStatus? status,
    List<Post>? posts,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
  }) {
    return UserPostsState(
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
