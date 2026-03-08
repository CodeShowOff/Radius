import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';

/// Full-screen reel video player card.
///
/// Plays the first video media item from the [NewsPost].
/// Supports tap-to-pause, mute toggle, and displays an overlay
/// with author info and caption.
class ReelPlayerCard extends StatefulWidget {
  final NewsPost reel;
  final bool isActive;

  const ReelPlayerCard({
    super.key,
    required this.reel,
    this.isActive = false,
  });

  @override
  State<ReelPlayerCard> createState() => _ReelPlayerCardState();
}

class _ReelPlayerCardState extends State<ReelPlayerCard> {
  VideoPlayerController? _controller;
  bool _isMuted = false;
  bool _showPauseIcon = false;
  bool _initError = false;

  MediaItem? get _videoItem {
    final items = widget.reel.mediaItems;
    if (items.isEmpty) return null;
    return items.firstWhere(
      (m) => m.type == PostMediaType.video,
      orElse: () => items.first,
    );
  }

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  @override
  void didUpdateWidget(covariant ReelPlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !(_controller?.value.isPlaying ?? false)) {
      _controller?.play();
    } else if (!widget.isActive && (_controller?.value.isPlaying ?? false)) {
      _controller?.pause();
    }
  }

  Future<void> _initPlayer() async {
    final video = _videoItem;
    if (video == null) return;

    final controller =
        VideoPlayerController.networkUrl(Uri.parse(video.url));

    try {
      await controller.initialize();
      controller.setLooping(true);
      if (widget.isActive) {
        await controller.play();
      }
      if (mounted) {
        setState(() => _controller = controller);
      } else {
        controller.dispose();
      }
    } catch (_) {
      controller.dispose();
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;

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
                          '${widget.reel.locality}, ${widget.reel.district}',
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

            // Right side — mute button
            Positioned(
              right: 12,
              bottom: 24,
              child: IconButton(
                onPressed: _toggleMute,
                icon: Icon(
                  _isMuted ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white,
                ),
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
    if (_initError) {
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
      final video = _videoItem;
      if (video?.thumbnailUrl != null) {
        return Image.network(
          video!.thumbnailUrl!,
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
