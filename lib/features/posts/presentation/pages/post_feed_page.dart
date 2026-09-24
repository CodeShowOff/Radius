import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../domain/entities/post.dart';
import '../../domain/repositories/i_post_interaction_repository.dart';
import '../bloc/post_feed_bloc.dart';
import '../bloc/post_interaction_cubit.dart';
import '../widgets/comments_bottom_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/post_shimmer.dart';

/// Main post feed page with infinite scroll and pull-to-refresh.
class PostFeedPage extends StatefulWidget {
  const PostFeedPage({super.key});

  @override
  State<PostFeedPage> createState() => _PostFeedPageState();
}

class _PostFeedPageState extends State<PostFeedPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFeed();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadFeed() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final connectionState = context.read<ConnectionBloc>().state;
    final connectionIds = connectionState.connections
        .map((c) => c.getOtherUserId(authState.user.id))
        .toList();

    context.read<PostFeedBloc>().add(PostFeedLoadRequested(
          userId: authState.user.id,
          connectionIds: connectionIds,
        ));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Load more when reaching 70% of scroll
    if (currentScroll >= maxScroll * 0.7) {
      final state = context.read<PostFeedBloc>().state;
      if (state.hasMore && !state.isLoadingMore) {
        context.read<PostFeedBloc>().add(const PostFeedLoadMore());
      }
    }
  }

  Future<void> _onRefresh() async {
    final completer = Completer<void>();
    context.read<PostFeedBloc>().add(PostFeedRefreshRequested(completer: completer));
    await completer.future;
  }

  Future<void> _navigateToCreatePost() async {
    final result = await context.push<bool>(Routes.createPost);
    if (result == true && mounted) {
      // Post was created â€” refresh feed
      context.read<PostFeedBloc>().add(const PostFeedRefreshRequested());
    }
  }

  void _confirmDelete(BuildContext context, String postId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text(
          'This post will be permanently deleted. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context
                  .read<PostFeedBloc>()
                  .add(PostFeedDeleteRequested(postId));
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _changeVisibility(
    BuildContext context,
    String postId,
    PostVisibility newVisibility,
  ) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final connectionState = context.read<ConnectionBloc>().state;
    final connectionIds = connectionState.connections
        .map((c) => c.getOtherUserId(authState.user.id))
        .toList();

    final label = newVisibility == PostVisibility.public
        ? 'public'
        : 'connections only';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Visibility?'),
        content: Text('Make this post visible to $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<PostFeedBloc>().add(PostFeedVisibilityChanged(
                    postId: postId,
                    newVisibility: newVisibility,
                    connectionIds: connectionIds,
                  ));
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        tooltip: 'Create Post',
        child: const Icon(Icons.add),
      ),
      body: BlocBuilder<PostFeedBloc, PostFeedState>(
        builder: (context, state) {
          if (state.status == PostFeedStatus.initial ||
              state.status == PostFeedStatus.loading) {
            return ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                PostCardSkeleton(),
                PostCardSkeleton(),
                PostCardSkeleton(),
              ],
            );
          }

          if (state.status == PostFeedStatus.error && state.posts.isEmpty) {
            return _ErrorView(
              message: state.errorMessage ?? 'Failed to load posts',
              onRetry: _loadFeed,
            );
          }

          if (state.posts.isEmpty) {
            return _EmptyFeedView(onCreatePost: _navigateToCreatePost);
          }

          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: state.posts.length + (state.isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.posts.length) {
                  // Loading indicator at the bottom
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final post = state.posts[index];
                final authState = context.read<AuthBloc>().state;
                final currentUserId = authState is AuthAuthenticated
                    ? authState.user.id
                    : '';
                final currentUserName = authState is AuthAuthenticated
                    ? (authState.user.displayName ?? authState.user.username)
                    : '';
                final currentUserPhoto = authState is AuthAuthenticated
                    ? authState.user.avatarUrl
                    : null;
                final isOwn = post.authorId == currentUserId;

                return BlocProvider(
                  key: ValueKey('interaction_${post.id}'),
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
                      isOwnPost: isOwn,
                      onAuthorTap: () {
                        context.push(Routes.userProfileWith(post.authorId));
                      },
                      onDelete: isOwn
                          ? () => _confirmDelete(context, post.id)
                          : null,
                      onVisibilityChange: isOwn
                          ? (v) => _changeVisibility(context, post.id, v)
                          : null,
                      onLikeTap: () {
                        cardContext.read<PostInteractionCubit>().toggleLike(
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
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// â”€â”€â”€ Empty Feed â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _EmptyFeedView extends StatelessWidget {
  final VoidCallback onCreatePost;

  const _EmptyFeedView({required this.onCreatePost});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dynamic_feed_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect with people to see their posts,\nor create your own!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreatePost,
              icon: const Icon(Icons.add),
              label: const Text('Create a Post'),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Error View â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
