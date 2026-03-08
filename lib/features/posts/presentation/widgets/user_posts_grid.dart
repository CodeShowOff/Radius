import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/post.dart';
import '../../domain/repositories/i_post_interaction_repository.dart';
import '../bloc/post_interaction_cubit.dart';
import '../bloc/user_posts_bloc.dart';
import 'comments_bottom_sheet.dart';
import 'post_card.dart';
import 'post_shimmer.dart';

/// Grid view of a user's posts (Instagram-style thumbnails).
///
/// Uses [UserPostsBloc] to load and paginate posts.
/// Shows media thumbnails in a 3-column grid, or a text icon for text-only posts.
class UserPostsGrid extends StatelessWidget {
  const UserPostsGrid({super.key});

  static void _showPostDetail(BuildContext context, Post post) {
    final authState = context.read<AuthBloc>().state;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';
    final currentUserName = authState is AuthAuthenticated
        ? (authState.user.displayName ?? authState.user.username)
        : '';
    final currentUserPhoto =
        authState is AuthAuthenticated ? authState.user.avatarUrl : null;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Theme.of(dialogContext).colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.8,
              ),
              child: SingleChildScrollView(
                child: BlocProvider(
                  create: (_) => PostInteractionCubit(
                    repository:
                        GetIt.instance<IPostInteractionRepository>(),
                  )..loadInteractionInfo(
                      postId: post.id,
                      userId: currentUserId,
                      initialLikeCount: post.likeCount,
                      initialCommentCount: post.commentCount,
                    ),
                  child: Builder(
                    builder: (cardContext) => PostCard(
                      post: post,
                      onLikeTap: () {
                        cardContext
                            .read<PostInteractionCubit>()
                            .toggleLike(
                              userName: currentUserName,
                              userPhotoUrl: currentUserPhoto,
                            );
                      },
                      onCommentTap: () {
                        CommentsBottomSheet.show(
                          context: cardContext,
                          postId: post.id,
                          currentUserId: currentUserId,
                          currentUserName: currentUserName,
                          currentUserPhotoUrl: currentUserPhoto,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserPostsBloc, UserPostsState>(
      builder: (context, state) {
        switch (state.status) {
          case UserPostsStatus.initial:
          case UserPostsStatus.loading:
            return const PostsGridSkeleton();

          case UserPostsStatus.error:
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.errorMessage ?? 'Failed to load posts',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => context
                          .read<UserPostsBloc>()
                          .add(const UserPostsRefreshRequested()),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );

          case UserPostsStatus.loaded:
            if (state.posts.isEmpty) {
              return const _EmptyPostsView();
            }

            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.pixels >=
                        notification.metrics.maxScrollExtent * 0.7) {
                  context
                      .read<UserPostsBloc>()
                      .add(const UserPostsLoadMore());
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final post = state.posts[index];
                        return GestureDetector(
                          onTap: () => _showPostDetail(context, post),
                          child: _PostGridTile(post: post),
                        );
                      },
                      childCount: state.posts.length,
                    ),
                  ),
                  if (state.isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            );
        }
      },
    );
  }
}

/// Single tile in the posts grid.
class _PostGridTile extends StatelessWidget {
  final Post post;

  const _PostGridTile({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // If no media, show text-based tile
    if (!post.hasMedia) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              post.text ?? '',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final firstMedia = post.mediaItems.first;

    // Video thumbnail
    if (firstMedia.type == PostMediaType.video) {
      final thumbUrl = firstMedia.thumbnailUrl ?? firstMedia.url;
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: thumbUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            errorWidget: (_, __, ___) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.videocam,
              color: Colors.white,
              size: 18,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
        ],
      );
    }

    // Image thumbnail
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: firstMedia.url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
        // Multi-media indicator
        if (post.hasMultipleMedia)
          Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.collections,
              color: Colors.white,
              size: 18,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
      ],
    );
  }
}

/// Empty state when a user has no posts.
class _EmptyPostsView extends StatelessWidget {
  const _EmptyPostsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Posts Yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
