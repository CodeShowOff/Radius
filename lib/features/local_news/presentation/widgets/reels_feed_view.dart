import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../bloc/news_interaction_cubit.dart';
import '../bloc/news_location_bloc.dart';
import '../bloc/reels_feed_bloc.dart';
import 'reel_player_card.dart';

/// Full-screen vertical-scrolling reels feed.
///
/// Uses [PreloadPageView] to render the next reel in the background before
/// the user swipes to it. Video playback logic is delegated to [ReelPlayerCard]
/// which uses VisibilityDetector to play/pause autonomously.
class ReelsFeedView extends StatefulWidget {
  const ReelsFeedView({super.key});

  @override
  State<ReelsFeedView> createState() => _ReelsFeedViewState();
}

class _ReelsFeedViewState extends State<ReelsFeedView> {
  final _pageController = PreloadPageController();

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
                      city: loc.city,
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

        return PreloadPageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          preloadPagesCount: 2, // Cache 2 pages ahead and behind for instant swiping
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
            final authState = context.read<AuthBloc>().state;
            final userId =
                authState is AuthAuthenticated ? authState.user.id : '';

            // We wrap each card in a provider so interactions work immediately
            return BlocProvider(
              create: (_) => NewsInteractionCubit(
                repository: getIt<INewsInteractionRepository>(),
              )..loadInteractionInfo(
                  postId: reel.id,
                  userId: userId,
                  initialLikeCount: reel.likeCount,
                  initialCommentCount: reel.commentCount,
                ),
              child: ReelPlayerCard(reel: reel),
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
