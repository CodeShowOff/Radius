part of 'news_interaction_cubit.dart';

/// State for news post interaction (likes & comments) for a single post.
class NewsInteractionState extends Equatable {
  final String? postId;
  final String? userId;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isLoaded;
  final bool isLikeInProgress;

  // Comments state
  final List<Comment> comments;
  final bool isLoadingComments;
  final bool isSubmittingComment;

  const NewsInteractionState({
    this.postId,
    this.userId,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.isLoaded = false,
    this.isLikeInProgress = false,
    this.comments = const [],
    this.isLoadingComments = false,
    this.isSubmittingComment = false,
  });

  NewsInteractionState copyWith({
    String? postId,
    String? userId,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    bool? isLoaded,
    bool? isLikeInProgress,
    List<Comment>? comments,
    bool? isLoadingComments,
    bool? isSubmittingComment,
  }) {
    return NewsInteractionState(
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLiked: isLiked ?? this.isLiked,
      isLoaded: isLoaded ?? this.isLoaded,
      isLikeInProgress: isLikeInProgress ?? this.isLikeInProgress,
      comments: comments ?? this.comments,
      isLoadingComments: isLoadingComments ?? this.isLoadingComments,
      isSubmittingComment: isSubmittingComment ?? this.isSubmittingComment,
    );
  }

  @override
  List<Object?> get props => [
        postId,
        userId,
        likeCount,
        commentCount,
        isLiked,
        isLoaded,
        isLikeInProgress,
        comments,
        isLoadingComments,
        isSubmittingComment,
      ];
}
