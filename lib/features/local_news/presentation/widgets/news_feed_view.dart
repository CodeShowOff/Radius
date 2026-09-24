import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart' as isp;

import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../bloc/news_feed_bloc.dart';
import '../bloc/news_interaction_cubit.dart';
import '../bloc/news_location_bloc.dart';
import 'news_comments_bottom_sheet.dart';
import 'news_post_card.dart';

class NewsFeedView extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final void Function(BuildContext, String) onConfirmDelete;

  const NewsFeedView({
    super.key,
    required this.onRefresh,
    required this.onConfirmDelete,
  });

  @override
  State<NewsFeedView> createState() => _NewsFeedViewState();
}

class _NewsFeedViewState extends State<NewsFeedView> {
  final isp.PagingController<int, NewsPost> _pagingController = isp.PagingController(firstPageKey: 0);

  @override
  void initState() {
    super.initState();
    
    // Sync initial state in case the bloc is already loaded when this tab is mounted
    final currentState = context.read<NewsFeedBloc>().state;
    if (currentState.status == NewsFeedStatus.loaded) {
      _pagingController.value = isp.PagingState(
        nextPageKey: currentState.hasMore ? currentState.posts.length : null,
        itemList: currentState.posts,
      );
    } else if (currentState.status == NewsFeedStatus.error && currentState.posts.isEmpty) {
      _pagingController.error = currentState.errorMessage ?? 'Error loading news feed';
    }

    _pagingController.addPageRequestListener((pageKey) {
      if (pageKey > 0) {
        context.read<NewsFeedBloc>().add(const NewsFeedLoadMore());
      } else if (currentState.status == NewsFeedStatus.initial || currentState.status == NewsFeedStatus.error) {
        final loc = context.read<NewsLocationBloc>().state.location;
        if (loc != null) {
          context.read<NewsFeedBloc>().add(NewsFeedLoadRequested(
            country: loc.country,
            city: loc.city,
          ));
        }
      }
    });
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : '';

    return BlocListener<NewsFeedBloc, NewsFeedState>(
      listener: (context, state) {
        if (state.status == NewsFeedStatus.loaded) {
          _pagingController.value = isp.PagingState(
            nextPageKey: state.hasMore ? state.posts.length : null,
            itemList: state.posts,
          );
        } else if (state.status == NewsFeedStatus.error && state.posts.isEmpty) {
          _pagingController.error = state.errorMessage ?? 'Error loading news';
        }
      },
      child: RefreshIndicator(
        onRefresh: () async {
          _pagingController.refresh();
          final loc = context.read<NewsLocationBloc>().state.location;
          if (loc != null) {
            context.read<NewsFeedBloc>().add(NewsFeedLoadRequested(
                  country: loc.country,
                  city: loc.city,
                ));
          }
          await widget.onRefresh();
        },
        child: isp.PagedListView<int, NewsPost>.separated(
          pagingController: _pagingController,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          separatorBuilder: (context, index) => Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.1)),
          builderDelegate: isp.PagedChildBuilderDelegate<NewsPost>(
            itemBuilder: (context, post, index) {
              final isOwn = post.authorId == currentUserId;
              return BlocProvider(
                key: ValueKey('news_interaction_${post.id}'),
                create: (_) => NewsInteractionCubit(
                  repository: getIt<INewsInteractionRepository>(),
                )..loadInteractionInfo(
                    postId: post.id,
                    userId: currentUserId,
                    initialLikeCount: post.likeCount,
                    initialCommentCount: post.commentCount,
                  ),
                child: Builder(
                  builder: (cardContext) => NewsPostCard(
                    post: post,
                    isOwnPost: isOwn,
                    onDelete: isOwn ? () => widget.onConfirmDelete(context, post.id) : null,
                    onLikeTap: () {
                      if (authState is AuthAuthenticated) {
                         cardContext.read<NewsInteractionCubit>().toggleLike(
                           userName: authState.user.displayName ?? 'User',
                           userPhotoUrl: authState.user.avatarUrl,
                         );
                      }
                    },
                    onCommentTap: () {
                      if (authState is AuthAuthenticated) {
                        NewsCommentsBottomSheet.show(
                          context: cardContext,
                          currentUserId: authState.user.id,
                          currentUserName: authState.user.displayName ?? 'User',
                          currentUserPhotoUrl: authState.user.avatarUrl,
                        );
                      }
                    },
                  ),
                ),
              );
            },
            firstPageProgressIndicatorBuilder: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            newPageProgressIndicatorBuilder: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            noItemsFoundIndicatorBuilder: (_) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_city, size: 64, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No local news found', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
