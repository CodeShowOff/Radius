import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/news_location.dart';
import '../bloc/news_feed_bloc.dart';
import '../bloc/news_location_bloc.dart';
import '../widgets/news_post_card.dart';

/// Main news feed page showing location-scoped news posts.
///
/// Shows a header with the current location and a change-location button.
/// Supports infinite-scroll pagination and pull-to-refresh.
class LocalNewsFeedPage extends StatefulWidget {
  const LocalNewsFeedPage({super.key});

  @override
  State<LocalNewsFeedPage> createState() => _LocalNewsFeedPageState();
}

class _LocalNewsFeedPageState extends State<LocalNewsFeedPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadFeed(NewsLocation location) {
    context.read<NewsFeedBloc>().add(NewsFeedLoadRequested(
          country: location.country,
          district: location.district,
        ));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Load more when reaching 70% of scroll
    if (currentScroll >= maxScroll * 0.7) {
      final state = context.read<NewsFeedBloc>().state;
      if (state.hasMore && !state.isLoadingMore) {
        context.read<NewsFeedBloc>().add(const NewsFeedLoadMore());
      }
    }
  }

  Future<void> _onRefresh() async {
    context.read<NewsFeedBloc>().add(const NewsFeedRefreshRequested());
    await context.read<NewsFeedBloc>().stream.first;
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
              context.read<NewsFeedBloc>().add(NewsFeedPostDeleted(postId));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<NewsLocationBloc, NewsLocationState>(
          builder: (context, locationState) {
            if (locationState.location != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Local News'),
                  Text(
                    locationState.location!.shortDisplayString,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            }
            return const Text('Local News');
          },
        ),
        actions: [
          // Change location button
          BlocBuilder<NewsLocationBloc, NewsLocationState>(
            builder: (context, locationState) {
              if (locationState.hasLocation) {
                return IconButton(
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  tooltip: 'Change Location',
                  onPressed: () {
                    context.read<NewsLocationBloc>().add(
                          const NewsLocationChangeRequested(),
                        );
                  },
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      // FAB to create a new news post (wired in Phase 5)
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.localNewsCreate),
        tooltip: 'Post News',
        child: const Icon(Icons.add),
      ),
      body: BlocListener<NewsLocationBloc, NewsLocationState>(
        listener: (context, locationState) {
          // When location becomes ready, load the feed
          if (locationState.status == NewsLocationStatus.ready &&
              locationState.location != null) {
            _loadFeed(locationState.location!);
          }
        },
        child: BlocBuilder<NewsFeedBloc, NewsFeedState>(
          builder: (context, state) {
            if (state.status == NewsFeedStatus.initial ||
                state.status == NewsFeedStatus.loading) {
              return _buildLoadingView();
            }

            if (state.status == NewsFeedStatus.error && state.posts.isEmpty) {
              return _ErrorView(
                message: state.errorMessage ?? 'Failed to load news',
                onRetry: () {
                  final loc =
                      context.read<NewsLocationBloc>().state.location;
                  if (loc != null) _loadFeed(loc);
                },
              );
            }

            if (state.posts.isEmpty) {
              return _EmptyFeedView(
                locationLabel: state.locationLabel,
              );
            }

            return _buildFeedList(context, state);
          },
        ),
      ),
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
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
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

          return NewsPostCard(
            post: post,
            isOwnPost: isOwn,
            onDelete: isOwn
                ? () => _confirmDelete(context, post.id)
                : null,
            onTap: () => context.push(
              Routes.localNewsPostWith(post.id),
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
