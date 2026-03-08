import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/news_location_bloc.dart';
import '../bloc/reels_feed_bloc.dart';
import 'reel_player_card.dart';

/// Full-screen vertical-scrolling reels feed.
///
/// Uses a [PageView] with vertical snapping to scroll between reels.
/// Triggers pagination when the user approaches the last few items.
class ReelsFeedView extends StatefulWidget {
  const ReelsFeedView({super.key});

  @override
  State<ReelsFeedView> createState() => _ReelsFeedViewState();
}

class _ReelsFeedViewState extends State<ReelsFeedView> {
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReelsFeedBloc, ReelsFeedState>(
      builder: (context, state) {
        if (state.status == ReelsFeedStatus.initial ||
            state.status == ReelsFeedStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.status == ReelsFeedStatus.error && state.reels.isEmpty) {
          return _ReelsErrorView(
            message: state.errorMessage ?? 'Failed to load reels',
            onRetry: () {
              final loc = context.read<NewsLocationBloc>().state.location;
              if (loc != null) {
                context.read<ReelsFeedBloc>().add(ReelsFeedLoadRequested(
                      country: loc.country,
                      district: loc.district,
                    ));
              }
            },
          );
        }

        if (state.reels.isEmpty) {
          return const _EmptyReelsView();
        }

        final totalCount =
            state.reels.length + (state.isLoadingMore ? 1 : 0);

        return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: totalCount,
          onPageChanged: (index) {
            // Trigger load-more when approaching the end
            if (index >= state.reels.length - 3 &&
                state.hasMore &&
                !state.isLoadingMore) {
              context.read<ReelsFeedBloc>().add(const ReelsFeedLoadMore());
            }
          },
          itemBuilder: (context, index) {
            if (index >= state.reels.length) {
              return const Center(child: CircularProgressIndicator());
            }

            final reel = state.reels[index];
            return ReelPlayerCard(
              reel: reel,
              isActive: true, // Managed by visibility
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty reels view
// ---------------------------------------------------------------------------
class _EmptyReelsView extends StatelessWidget {
  const _EmptyReelsView();

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
              Icons.videocam_off_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No reels yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share a reel in your area!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error view for reels
// ---------------------------------------------------------------------------
class _ReelsErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ReelsErrorView({required this.message, required this.onRetry});

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
