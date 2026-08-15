import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:share_plus/share_plus.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';
import '../bloc/news_interaction_cubit.dart';
import 'news_comments_bottom_sheet.dart';

/// Full-screen reel video player card.
///
/// This card is autonomous: it downloads/caches its own video using
/// [DefaultCacheManager], initializes its [VideoPlayerController], and
/// automatically plays/pauses based on its visibility using [VisibilityDetector].
class ReelPlayerCard extends StatefulWidget {
  final NewsPost reel;

  const ReelPlayerCard({
    super.key,
    required this.reel,
  });

  @override
  State<ReelPlayerCard> createState() => _ReelPlayerCardState();
}

class _ReelPlayerCardState extends State<ReelPlayerCard> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _showPauseIcon = false;
  bool _hasError = false;
  bool _isInitialized = false;
  bool _isMuted = false;

  final Stopwatch _watchStopwatch = Stopwatch();
  int _totalAccumulatedWatchMs = 0;
  bool _watchReported = false;
  late final NewsInteractionCubit _cubit;
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<NewsInteractionCubit>();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _initVideo();
  }

  @override
  void dispose() {
    _reportWatchTime();
    _spinController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _reportWatchTime() {
    if (_watchReported) return;
    _watchReported = true;

    if (_watchStopwatch.isRunning) {
      _watchStopwatch.stop();
      _totalAccumulatedWatchMs += _watchStopwatch.elapsedMilliseconds;
    }

    if (_totalAccumulatedWatchMs > 0) {
      final totalMs = (_controller != null && _controller!.value.isInitialized)
          ? _controller!.value.duration.inMilliseconds
          : 0;
      
      _cubit.recordWatchTime(
        watchedMs: _totalAccumulatedWatchMs,
        totalMs: totalMs,
      );
    }
  }

  Future<void> _initVideo() async {
    final url = _videoUrlFor(widget.reel);
    if (url == null) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
      return;
    }

    try {
      // Download or get cached file using flutter_cache_manager
      final file = await DefaultCacheManager().getSingleFile(url);

      if (!mounted) return;

      final controller = VideoPlayerController.file(file);
      _controller = controller;

      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(_isMuted ? 0.0 : 1.0);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  String? _videoUrlFor(NewsPost reel) {
    final items = reel.mediaItems;
    if (items.isEmpty) return null;
    final video = items.cast<MediaItem?>().firstWhere(
          (m) => m!.type == PostMediaType.video,
          orElse: () => null,
        );
    return video?.url;
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (info.visibleFraction >= 0.8) {
      if (!_watchStopwatch.isRunning) {
        _watchStopwatch.start();
      }
      if (!c.value.isPlaying) {
        c.play();
        if (mounted) {
          setState(() {
            _showPauseIcon = false;
          });
        }
      }
      if (!_spinController.isAnimating) _spinController.repeat();
    } else {
      if (_watchStopwatch.isRunning) {
        _watchStopwatch.stop();
        _totalAccumulatedWatchMs += _watchStopwatch.elapsedMilliseconds;
        _watchStopwatch.reset();
      }
      if (c.value.isPlaying) {
        c.pause();
      }
      _spinController.stop();
    }
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _showPauseIcon = true;
        _spinController.stop();
      } else {
        c.play();
        _showPauseIcon = false;
        _spinController.repeat();
      }
    });
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    setState(() {
      _isMuted = !_isMuted;
      c.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }


  void _onLikeTap(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    context.read<NewsInteractionCubit>().toggleLike(
          userName: authState.user.displayName ?? authState.user.username,
          userPhotoUrl: authState.user.avatarUrl,
        );
  }

  void _onCommentTap(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    NewsCommentsBottomSheet.show(
      context: context,
      currentUserId: authState.user.id,
      currentUserName: authState.user.displayName ?? authState.user.username,
      currentUserPhotoUrl: authState.user.avatarUrl,
    );
  }

  void _onShareTap(BuildContext context) {
    final textToShare = widget.reel.text != null && widget.reel.text!.isNotEmpty
        ? 'Check out this reel by ${widget.reel.authorName}: ${widget.reel.text}'
        : 'Check out this reel by ${widget.reel.authorName} on Radius!';
    
    SharePlus.instance.share(ShareParams(text: textToShare)).then((_) {
      if (!context.mounted) return;
      context.read<NewsInteractionCubit>().recordShare();
    });
  }

  static String _formatCount(int count) {
    if (count == 0) return '';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return VisibilityDetector(
      key: Key('reel_${widget.reel.id}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video or placeholder
              _buildVideoLayer(theme),

              // Pause icon overlay
              if (_showPauseIcon)
                const Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 72,
                    color: Colors.white70,
                  ),
                ),

              // Top Gradient & "Reels" Header
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 120,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Reels',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const Icon(CupertinoIcons.camera, color: Colors.white, size: 28),
                  ],
                ),
              ),

              // Bottom gradient for text readability (taller & smoother)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 350,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Left overlay — author, caption, audio track
              Positioned(
                left: 16,
                right: 70,
                bottom: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Author row with Follow button
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: widget.reel.authorPhotoUrl != null
                                  ? NetworkImage(widget.reel.authorPhotoUrl!)
                                  : null,
                              child: widget.reel.authorPhotoUrl == null
                                  ? Text(
                                      widget.reel.authorName.isNotEmpty
                                          ? widget.reel.authorName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                          fontSize: 14, color: Colors.white),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            widget.reel.authorName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Follow',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Caption
                    if (widget.reel.text != null &&
                        widget.reel.text!.isNotEmpty) ...[
                      Text(
                        widget.reel.text!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Audio Track Row
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.music_note_2,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${widget.reel.authorName} • Original Audio',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.reel.locationLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right side — interaction buttons + mute
              Positioned(
                right: 8,
                bottom: 24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Like button
                    BlocBuilder<NewsInteractionCubit, NewsInteractionState>(
                      buildWhen: (prev, curr) =>
                          prev.isLiked != curr.isLiked ||
                          prev.likeCount != curr.likeCount,
                      builder: (context, state) {
                        return _ReelActionButton(
                          icon: state.isLiked
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.heart,
                          label: _formatCount(state.likeCount),
                          color: state.isLiked ? Colors.red : Colors.white,
                          onTap: () => _onLikeTap(context),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Comment button
                    BlocBuilder<NewsInteractionCubit, NewsInteractionState>(
                      buildWhen: (prev, curr) =>
                          prev.commentCount != curr.commentCount,
                      builder: (context, state) {
                        return _ReelActionButton(
                          icon: CupertinoIcons.chat_bubble,
                          label: _formatCount(state.commentCount),
                          color: Colors.white,
                          onTap: () => _onCommentTap(context),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Share button
                    _ReelActionButton(
                      icon: CupertinoIcons.paperplane,
                      label: 'Share',
                      color: Colors.white,
                      onTap: () => _onShareTap(context),
                    ),
                    const SizedBox(height: 16),
                    // Mute toggle button
                    _ReelActionButton(
                      icon: _isMuted
                          ? CupertinoIcons.speaker_slash
                          : CupertinoIcons.speaker_3,
                      label: '',
                      color: Colors.white,
                      onTap: _toggleMute,
                    ),
                    const SizedBox(height: 16),
                    // More button
                    _ReelActionButton(
                      icon: Icons.more_vert,
                      label: '',
                      color: Colors.white,
                      onTap: () {}, // Optional menu
                    ),
                    const SizedBox(height: 16),
                    // Spinning audio disc
                    AnimatedBuilder(
                      animation: _spinController,
                      builder: (_, child) {
                        return Transform.rotate(
                          angle: _spinController.value * 2 * math.pi,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                          color: Colors.black87,
                          image: widget.reel.authorPhotoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.reel.authorPhotoUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: widget.reel.authorPhotoUrl == null
                            ? const Icon(CupertinoIcons.music_note, color: Colors.white, size: 20)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),

              // Video progress at the very bottom
              if (_isInitialized)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: theme.colorScheme.primary,
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoLayer(ThemeData theme) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text(
              'Could not load video',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      // Show thumbnail while loading
      final items = widget.reel.mediaItems;
      final thumbnailUrl = items.isNotEmpty ? items.first.thumbnailUrl : null;
      if (thumbnailUrl != null) {
        return Image.network(
          thumbnailUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: CircularProgressIndicator()),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable action button for the reel overlay (TikTok-style)
// ---------------------------------------------------------------------------
class _ReelActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ReelActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
