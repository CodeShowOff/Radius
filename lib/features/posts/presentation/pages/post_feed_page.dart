import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart' as isp;

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

/// Premium Post Feed Page utilizing Infinite Scroll Pagination
class PostFeedPage extends StatefulWidget {
  const PostFeedPage({super.key});

  @override
  State<PostFeedPage> createState() => _PostFeedPageState();
}

class _PostFeedPageState extends State<PostFeedPage> {
  final isp.PagingController<int, Post> _pagingController = isp.PagingController(firstPageKey: 0);

  @override
  void initState() {
    super.initState();
    _pagingController.addPageRequestListener((pageKey) {
      if (pageKey == 0) {
        _loadInitialFeed();
      } else {
        context.read<PostFeedBloc>().add(const PostFeedLoadMore());
      }
    });
  }

  void _loadInitialFeed() {
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

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<void> _navigateToCreatePost() async {
    final result = await context.push<bool>(Routes.createPost);
    if (result == true && mounted) {
      _pagingController.refresh();
    }
  }

  void _confirmDelete(BuildContext context, String postId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<PostFeedBloc>().add(PostFeedDeleteRequested(postId));
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

  void _changeVisibility(BuildContext context, String postId, PostVisibility newVisibility) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final connectionState = context.read<ConnectionBloc>().state;
    final connectionIds = connectionState.connections
        .map((c) => c.getOtherUserId(authState.user.id))
        .toList();

    context.read<PostFeedBloc>().add(PostFeedVisibilityChanged(
      postId: postId,
      newVisibility: newVisibility,
      connectionIds: connectionIds,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreatePost,
        child: const Icon(Icons.add),
      ),
      body: BlocListener<PostFeedBloc, PostFeedState>(
        listener: (context, state) {
          if (state.status == PostFeedStatus.loaded) {
            _pagingController.value = isp.PagingState(
              nextPageKey: state.hasMore ? (state.posts.length) : null,
              itemList: state.posts,
            );
          } else if (state.status == PostFeedStatus.error && state.posts.isEmpty) {
            _pagingController.error = state.errorMessage;
          }
        },
        child: RefreshIndicator(
          onRefresh: () async {
            _pagingController.refresh();
          },
          child: isp.PagedListView<int, Post>.separated(
            pagingController: _pagingController,
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            separatorBuilder: (context, index) => Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.1)),
            builderDelegate: isp.PagedChildBuilderDelegate<Post>(
              itemBuilder: (context, post, index) {
                final authState = context.read<AuthBloc>().state;
                final currentUserId = authState is AuthAuthenticated ? authState.user.id : '';
                final currentUserName = authState is AuthAuthenticated ? (authState.user.displayName ?? authState.user.username) : '';
                final currentUserPhoto = authState is AuthAuthenticated ? authState.user.avatarUrl : null;
                final isOwn = post.authorId == currentUserId;

                return BlocProvider(
                  key: ValueKey('interaction_${post.id}'),
                  create: (_) => PostInteractionCubit(
                    repository: GetIt.instance<IPostInteractionRepository>(),
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
                      onAuthorTap: () => context.push(Routes.userProfileWith(post.authorId)),
                      onDelete: isOwn ? () => _confirmDelete(context, post.id) : null,
                      onVisibilityChange: isOwn ? (v) => _changeVisibility(context, post.id, v) : null,
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
              firstPageProgressIndicatorBuilder: (_) => const Column(
                children: [PostCardSkeleton(), PostCardSkeleton()],
              ),
              newPageProgressIndicatorBuilder: (_) => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              noItemsFoundIndicatorBuilder: (_) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.style, size: 64, color: theme.colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('No posts yet', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _navigateToCreatePost,
                      child: const Text('Create the first post'),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
