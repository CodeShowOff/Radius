import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/di/injection.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_interaction_repository.dart';
import '../bloc/news_interaction_cubit.dart';
import '../bloc/news_location_bloc.dart';
import '../bloc/reels_feed_bloc.dart';
import 'reel_player_card.dart';

/// Full-screen vertical-scrolling reels feed.
///
/// Uses a [PageView] with vertical snapping to scroll between reels.
/// Pre-caches video controllers for the current reel and the next 2,
/// disposing controllers that fall outside the cache window.
class ReelsFeedView extends StatefulWidget {
  const ReelsFeedView({super.key});

  @override
  State<ReelsFeedView> createState() => _ReelsFeedViewState();
}

class _ReelsFeedViewState extends State<ReelsFeedView> {
  final _pageController = PageController();
  int _currentPage = 0;

  /// Cache window: keep controllers for [current-1 .. current+2].
  static const int _cacheBeforeCount = 1;
  static const int _cacheAfterCount = 2;

  /// Reel ID -> cached controller entry.
  final Map<String, _CachedController> _controllers = {};

  /// The list of reels from the last build, used for cache management.
  List<NewsPost> _reels = const [];

  @override
  void dispose() {
    _disposeAllControllers();
    _pageController.dispose();
    super.dispose();
  }

  // ─── Cache management ─────────────────────────────────────────────

  /// Returns the video URL for a reel, or null if none.
  String? _videoUrlFor(NewsPost reel) {
    final items = reel.mediaItems;
    if (items.isEmpty) return null;
    final video = items.cast<MediaItem?>().firstWhere(
          (m) => m!.type == PostMediaType.video,
          orElse: () => null,
        );
    return video?.url;
  }

  /// Updates the controller cache based on the current page.
  /// Initializes controllers within the window and disposes those outside.
  void _updateCache(List<NewsPost> reels) {
    _reels = reels;
    if (reels.isEmpty) {
      _disposeAllControllers();
      return;
    }

    final start = (_currentPage - _cacheBeforeCount).clamp(0, reels.length - 1);
    final end = (_currentPage + _cacheAfterCount).clamp(0, reels.length - 1);

    // Collect IDs that should be in the cache
    final activeIds = <String>{};
    for (var i = start; i <= end; i++) {
      activeIds.add(reels[i].id);
    }

    // Dispose controllers outside the window
    final toRemove = _controllers.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in toRemove) {
      _controllers[id]?.dispose();
      _controllers.remove(id);
    }

    // Initialize controllers within the window that don't exist yet
    for (var i = start; i <= end; i++) {
      final reel = reels[i];
      if (!_controllers.containsKey(reel.id)) {
        _initController(reel, shouldPlay: i == _currentPage);
      }
    }
  }

  Future<void> _initController(NewsPost reel, {bool shouldPlay = false}) async {
    final url = _videoUrlFor(reel);
    if (url == null) return;

    final entry = _CachedController();
    _controllers[reel.id] = entry;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    entry.controller = controller;

    try {
      await controller.initialize();
      controller.setLooping(true);
      if (shouldPlay && mounted) {
        await controller.play();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      entry.hasError = true;
      if (mounted) setState(() {});
    }
  }

  void _onPageChanged(int index) {
    final previous = _currentPage;
    _currentPage = index;

    // Pause the previous reel
    if (previous < _reels.length) {
      final prevEntry = _controllers[_reels[previous].id];
      prevEntry?.controller?.pause();
    }

    // Play the current reel (seek to start for a fresh view)
    if (index < _reels.length) {
      final curEntry = _controllers[_reels[index].id];
      final c = curEntry?.controller;
      if (c != null && c.value.isInitialized) {
        c.seekTo(Duration.zero);
        c.play();
      }
    }

    // Update the cache window for pre-caching next reels
    _updateCache(_reels);

    setState(() {});
  }

  void _disposeAllControllers() {
    for (final entry in _controllers.values) {
      entry.dispose();
    }
    _controllers.clear();
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

        // Ensure cache is up-to-date when reels list changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateCache(state.reels);
        });

        final totalCount =
            state.reels.length + (state.isLoadingMore ? 1 : 0);

        return PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: totalCount,
          onPageChanged: (index) {
            _onPageChanged(index);
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
            final entry = _controllers[reel.id];
            final authState = context.read<AuthBloc>().state;
            final userId =
                authState is AuthAuthenticated ? authState.user.id : '';

            return BlocProvider(
              create: (_) => NewsInteractionCubit(
                repository: getIt<INewsInteractionRepository>(),
              )..loadInteractionInfo(
                  postId: reel.id,
                  userId: userId,
                  initialLikeCount: reel.likeCount,
                  initialCommentCount: reel.commentCount,
                ),
              child: ReelPlayerCard(
                reel: reel,
                isActive: index == _currentPage,
                controller: entry?.controller,
                controllerError: entry?.hasError ?? false,
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Cached controller entry
// ---------------------------------------------------------------------------
class _CachedController {
  VideoPlayerController? controller;
  bool hasError = false;

  void dispose() {
    controller?.dispose();
    controller = null;
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
