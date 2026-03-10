import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/news_post.dart';
import '../bloc/news_interaction_cubit.dart';
import 'news_comments_bottom_sheet.dart';

/// Full-screen reel video player card.
///
/// Receives an externally-managed [VideoPlayerController] from the parent
/// feed widget which handles pre-caching and lifecycle.
/// Supports tap-to-pause, mute toggle, and displays an overlay
/// with author info and caption.
class ReelPlayerCard extends StatefulWidget {
  final NewsPost reel;
  final bool isActive;

  /// Externally managed controller (may be null while initializing).
  final VideoPlayerController? controller;

  /// Whether the external controller had an initialization error.
  final bool controllerError;

  const ReelPlayerCard({
    super.key,
    required this.reel,
    this.isActive = false,
    this.controller,
    this.controllerError = false,
  });

  @override
  State<ReelPlayerCard> createState() => _ReelPlayerCardState();
}

class _ReelPlayerCardState extends State<ReelPlayerCard> {
  bool _isMuted = false;
  bool _showPauseIcon = false;

  VideoPlayerController? get _controller => widget.controller;

  @override
  void didUpdateWidget(covariant ReelPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    if (widget.isActive && !c.value.isPlaying) {
      c.seekTo(Duration.zero);
      c.play();
      _showPauseIcon = false;
    } else if (!widget.isActive && c.value.isPlaying) {
      c.pause();
    }
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _showPauseIcon = true;
      } else {
        c.play();
        _showPauseIcon = false;
      }
    });
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _isMuted = !_isMuted;
      c.setVolume(_isMuted ? 0 : 1);
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

  static String _formatCount(int count) {
    if (count == 0) return '';
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
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

            // Bottom gradient for text readability
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom overlay — author + caption
            Positioned(
              left: 16,
              right: 60,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Author row
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
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
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.reel.authorName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Caption
                  if (widget.reel.text != null &&
                      widget.reel.text!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.reel.text!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // Location
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.reel.locationLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
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
              bottom: 80,
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
                            ? Icons.favorite
                            : Icons.favorite_border,
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
                        icon: Icons.chat_bubble_outline,
                        label: _formatCount(state.commentCount),
                        color: Colors.white,
                        onTap: () => _onCommentTap(context),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Share button
                  _ReelActionButton(
                    icon: Icons.share_outlined,
                    label: '',
                    color: Colors.white,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Share will be available soon!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Mute button
                  _ReelActionButton(
                    icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                    label: '',
                    color: Colors.white,
                    onTap: _toggleMute,
                  ),
                ],
              ),
            ),

            // Video progress at the very bottom
            if (_controller != null)
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
    );
  }

  Widget _buildVideoLayer(ThemeData theme) {
    if (widget.controllerError) {
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

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
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
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
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
          Icon(icon, size: 28, color: color),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
