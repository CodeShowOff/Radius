import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart' as isp;

import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../bloc/reels_feed_bloc.dart';
import '../bloc/news_interaction_cubit.dart';
import '../bloc/news_location_bloc.dart';
import 'reel_player_card.dart';

class ReelsFeedView extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final void Function(BuildContext, String) onConfirmDelete;

  const ReelsFeedView({
    super.key,
    required this.onRefresh,
    required this.onConfirmDelete,
  });

  @override
  State<ReelsFeedView> createState() => _ReelsFeedViewState();
}

class _ReelsFeedViewState extends State<ReelsFeedView> {
  final isp.PagingController<int, NewsPost> _pagingController = isp.PagingController(firstPageKey: 0);

  @override
  void initState() {
    super.initState();
    _pagingController.addPageRequestListener((pageKey) {
      if (pageKey > 0) {
        context.read<ReelsFeedBloc>().add(const ReelsFeedLoadMore());
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

    return BlocListener<ReelsFeedBloc, ReelsFeedState>(
      listener: (context, state) {
        if (state.status == ReelsFeedStatus.loaded) {
          _pagingController.value = isp.PagingState(
            nextPageKey: state.hasMore ? state.reels.length : null,
            itemList: state.reels,
          );
        } else if (state.status == ReelsFeedStatus.error && state.reels.isEmpty) {
          _pagingController.error = state.errorMessage ?? 'Error loading reels';
        }
      },
      child: RefreshIndicator(
        onRefresh: () async {
          _pagingController.refresh();
          final loc = context.read<NewsLocationBloc>().state.location;
          if (loc != null) {
            context.read<ReelsFeedBloc>().add(ReelsFeedLoadRequested(
                  country: loc.country,
                  city: loc.city,
                ));
          }
          await widget.onRefresh();
        },
        child: isp.PagedPageView<int, NewsPost>(
          pagingController: _pagingController,
          scrollDirection: Axis.vertical,
          builderDelegate: isp.PagedChildBuilderDelegate<NewsPost>(
            itemBuilder: (context, post, index) {
              final isOwn = post.authorId == currentUserId;
              return BlocProvider(
                key: ValueKey('reel_interaction_${post.id}'),
                create: (_) => NewsInteractionCubit(
                  repository: getIt<INewsInteractionRepository>(),
                )..loadInteractionInfo(
                    postId: post.id,
                    userId: currentUserId,
                    initialLikeCount: post.likeCount,
                    initialCommentCount: post.commentCount,
                  ),
                child: Builder(
                  builder: (cardContext) => ReelPlayerCard(
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
                       // Implement comments bottom sheet
                    },
                  ),
                ),
              );
            },
            firstPageProgressIndicatorBuilder: (_) => const Center(child: CircularProgressIndicator()),
            newPageProgressIndicatorBuilder: (_) => const Center(child: CircularProgressIndicator()),
            noItemsFoundIndicatorBuilder: (_) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.video_collection, size: 64, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No reels found', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
