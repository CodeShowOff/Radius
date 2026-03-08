part of 'user_posts_bloc.dart';

/// Base class for user posts events.
abstract class UserPostsEvent extends Equatable {
  const UserPostsEvent();

  @override
  List<Object?> get props => [];
}

/// Load posts for a specific user's profile.
class UserPostsLoadRequested extends UserPostsEvent {
  /// The user whose posts to load.
  final String userId;

  /// The viewer's user ID (for visibility filtering).
  final String viewerUserId;

  /// Whether the viewer is connected to this user.
  final bool isConnection;

  const UserPostsLoadRequested({
    required this.userId,
    required this.viewerUserId,
    required this.isConnection,
  });

  @override
  List<Object?> get props => [userId, viewerUserId, isConnection];
}

/// Load more posts (next page).
class UserPostsLoadMore extends UserPostsEvent {
  const UserPostsLoadMore();
}

/// Refresh user posts.
class UserPostsRefreshRequested extends UserPostsEvent {
  const UserPostsRefreshRequested();
}

/// Delete a post.
class UserPostsDeleteRequested extends UserPostsEvent {
  final String postId;

  const UserPostsDeleteRequested(this.postId);

  @override
  List<Object?> get props => [postId];
}

/// Change visibility of a post.
class UserPostsVisibilityChanged extends UserPostsEvent {
  final String postId;
  final PostVisibility newVisibility;
  final List<String> connectionIds;

  const UserPostsVisibilityChanged({
    required this.postId,
    required this.newVisibility,
    required this.connectionIds,
  });

  @override
  List<Object?> get props => [postId, newVisibility, connectionIds];
}
