import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/news_post.dart';

class ReelPlayerCard extends StatefulWidget {
  final NewsPost post;
  final bool isOwnPost;
  final VoidCallback? onDelete;
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;
  
  final int? likeCount;
  final int? commentCount;
  final bool isLiked;

  const ReelPlayerCard({
    super.key,
    required this.post,
    this.isOwnPost = false,
    this.onDelete,
    this.onLikeTap,
    this.onCommentTap,
    this.likeCount,
    this.commentCount,
    this.isLiked = false,
  });

  @override
  State<ReelPlayerCard> createState() => _ReelPlayerCardState();
}

class _ReelPlayerCardState extends State<ReelPlayerCard> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;

  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    final urls = widget.post.mediaItems.map((m) => m.url).toList();
    if (urls.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(urls.first))
        ..initialize().then((_) {
          _controller?.setLooping(true);
          if (mounted) {
            setState(() {});
            if (_isVisible) {
              _controller?.play();
              _isPlaying = true;
            }
          }
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() {
      _isPlaying = _controller!.value.isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    
    
    return VisibilityDetector(
      key: Key('reel_${widget.post.id}'),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        _isVisible = info.visibleFraction > 0.7;
        
        if (_isVisible) {
          _controller?.play();
          setState(() => _isPlaying = true);
        } else {
          _controller?.pause();
          setState(() => _isPlaying = false);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video Layer
          if (_controller != null && _controller!.value.isInitialized)
            GestureDetector(
              onTap: _togglePlay,
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            Container(color: Colors.black, child: const Center(child: CircularProgressIndicator())),

          // Gradient Overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),

          // Play/Pause Indicator
          if (!_isPlaying && _controller != null && _controller!.value.isInitialized)
            const Center(
              child: Icon(Icons.play_arrow, size: 64, color: Colors.white54),
            ),

          // UI Layer
          Positioned(
            bottom: 16,
            left: 16,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CachedAvatar(imageUrl: widget.post.authorPhotoUrl, name: widget.post.authorName, radius: 18),
                    const SizedBox(width: 8),
                    Text(widget.post.authorName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                if ((widget.post.text ?? '').isNotEmpty)
                  Text(
                    (widget.post.text ?? ''),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text('${widget.post.city}, ${widget.post.country}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),

          // Action Buttons
          Positioned(
            bottom: 100,
            right: 8,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: widget.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: widget.isLiked ? Colors.red : Colors.white,
                  label: '${widget.likeCount ?? widget.post.likeCount}',
                  onTap: widget.onLikeTap,
                ),
                const SizedBox(height: 16),
                _ActionButton(
                  icon: Icons.comment,
                  label: '${widget.commentCount ?? widget.post.commentCount}',
                  onTap: widget.onCommentTap,
                ),
                if (widget.isOwnPost)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _ActionButton(
                      icon: Icons.delete,
                      label: '',
                      onTap: widget.onDelete,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, required this.label, this.color = Colors.white, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }
}
