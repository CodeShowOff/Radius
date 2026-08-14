import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../bloc/news_feed_bloc.dart';
import '../bloc/news_interaction_cubit.dart';
import '../bloc/news_location_bloc.dart';
import 'news_post_card.dart';

class NewsFeedView extends StatelessWidget {
  final ScrollController scrollController;
  final Future<void> Function() onRefresh;
  final void Function(BuildContext, String) onConfirmDelete;

  const NewsFeedView({
    super.key,
    required this.scrollController,
    required this.onRefresh,
    required this.onConfirmDelete,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NewsFeedBloc, NewsFeedState>(
      builder: (context, state) {
        if (state.status == NewsFeedStatus.initial ||
            state.status == NewsFeedStatus.loading) {
          return _buildLoadingView();
        }

        if (state.status == NewsFeedStatus.error && state.posts.isEmpty) {
          return _ErrorView(
            message: state.errorMessage ?? 'Failed to load news',
            onRetry: () {
              final loc = context.read<NewsLocationBloc>().state.location;
              if (loc != null) {
                context.read<NewsFeedBloc>().add(NewsFeedLoadRequested(
                      country: loc.country,
                      city: loc.city,
                    ));
              }
            },
          );
        }

        if (state.posts.isEmpty) {
          return _EmptyFeedView(locationLabel: state.locationLabel);
        }

        return _buildFeedList(context, state);
      },
    );
  }

  Widget _buildLoadingView() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        _NewsCardSkeleton(),
        _NewsCardSkeleton(),
        _NewsCardSkeleton(),
      ],
    );
  }

  Widget _buildFeedList(BuildContext context, NewsFeedState state) {
    final authState = context.read<AuthBloc>().state;
    final currentUserId =
        authState is AuthAuthenticated ? authState.user.id : '';

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scrollController,
        itemCount: state.posts.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final post = state.posts[index];
          final isOwn = post.authorId == currentUserId;

          return BlocProvider(
            create: (_) => NewsInteractionCubit(
              repository: getIt<INewsInteractionRepository>(),
            )..loadInteractionInfo(
                postId: post.id,
                userId: currentUserId,
                initialLikeCount: post.likeCount,
                initialCommentCount: post.commentCount,
              ),
            child: NewsPostCard(
              post: post,
              isOwnPost: isOwn,
              onDelete: isOwn
                  ? () => onConfirmDelete(context, post.id)
                  : null,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty feed view
// ---------------------------------------------------------------------------
class _EmptyFeedView extends StatelessWidget {
  final String locationLabel;

  const _EmptyFeedView({required this.locationLabel});

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
              Icons.newspaper_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No local news yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              locationLabel.isNotEmpty
                  ? 'There are no news posts in $locationLabel yet.\nBe the first to post!'
                  : 'Be the first to post news in your area!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push(Routes.localNewsCreate),
              icon: const Icon(Icons.add),
              label: const Text('Post News'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

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

// ---------------------------------------------------------------------------
// Simple loading skeleton for news cards
// ---------------------------------------------------------------------------
class _NewsCardSkeleton extends StatelessWidget {
  const _NewsCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHighest;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header skeleton
            Row(
              children: [
                CircleAvatar(radius: 20, backgroundColor: color),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 80,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Media skeleton
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            // Text skeleton
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 200,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
