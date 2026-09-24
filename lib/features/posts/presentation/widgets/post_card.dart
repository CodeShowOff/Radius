import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/post.dart';
import '../bloc/post_interaction_cubit.dart';

/// Card widget displaying a single post in the feed.
///
/// Handles text-only, single image/video, and multi-media carousel posts.
class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onAuthorTap;
  final bool isOwnPost;
  final VoidCallback? onDelete;
  final ValueChanged<PostVisibility>? onVisibilityChange;
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;

  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
    this.isOwnPost = false,
    this.onDelete,
    this.onVisibilityChange,
    this.onLikeTap,
    this.onCommentTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author header
          _PostHeader(
            authorName: post.authorName,
            authorPhotoUrl: post.authorPhotoUrl,
            createdAt: post.createdAt,
            visibility: post.visibility,
            onTap: onAuthorTap,
            isOwnPost: isOwnPost,
            onDelete: onDelete,
            onVisibilityChange: onVisibilityChange,
          ),

          // Media content
          if (post.hasMedia)
            post.hasMultipleMedia
                ? _MediaCarousel(mediaItems: post.mediaItems)
                : _SingleMedia(mediaItem: post.mediaItems.first),

          // Text content
          if (post.text != null && post.text!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                post.text!,
                style: theme.textTheme.bodyMedium,
              ),
            ),

          // Like / Comment action bar
          _PostActionBar(
            onLikeTap: onLikeTap,
            onCommentTap: onCommentTap,
          ),

          // Divider
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Post Action Bar (Like / Comment) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PostActionBar extends StatelessWidget {
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;

  const _PostActionBar({
    this.onLikeTap,
    this.onCommentTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<PostInteractionCubit, PostInteractionState>(
      buildWhen: (prev, curr) =>
          prev.isLiked != curr.isLiked ||
          prev.likeCount != curr.likeCount ||
          prev.commentCount != curr.commentCount,
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action buttons row
              Row(
                children: [
                  // Like button
                  _AnimatedLikeButton(
                    isLiked: state.isLiked,
                    onTap: onLikeTap,
                  ),
                  const SizedBox(width: 4),
                  // Comment button
                  IconButton(
                    icon: Icon(
                      Icons.chat_bubble_outline,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: onCommentTap,
                    tooltip: 'Comment',
                  ),
                  const SizedBox(width: 4),
                  // Share button
                  IconButton(
                    icon: Icon(
                      Icons.share_outlined,
                      color: theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Share will be available soon!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    tooltip: 'Share',
                  ),
                ],
              ),
              // Like count
              if (state.likeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    state.likeCount == 1
                        ? '1 like'
                        : '${_formatCount(state.likeCount)} likes',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // Comment count as tappable text
              if (state.commentCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: GestureDetector(
                    onTap: onCommentTap,
                    child: Text(
                      state.commentCount == 1
                          ? 'View 1 comment'
                          : 'View all ${_formatCount(state.commentCount)} comments',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// â”€â”€â”€ Animated Like Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AnimatedLikeButton extends StatefulWidget {
  final bool isLiked;
  final VoidCallback? onTap;

  const _AnimatedLikeButton({
    required this.isLiked,
    this.onTap,
  });

  @override
  State<_AnimatedLikeButton> createState() => _AnimatedLikeButtonState();
}

class _AnimatedLikeButtonState extends State<_AnimatedLikeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _AnimatedLikeButton old) {
    super.didUpdateWidget(old);
    if (widget.isLiked && !old.isLiked) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: IconButton(
        icon: Icon(
          widget.isLiked ? Icons.favorite : Icons.favorite_border,
          color: widget.isLiked ? Colors.red : Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: widget.onTap,
        tooltip: widget.isLiked ? 'Unlike' : 'Like',
      ),
    );
  }
}

// â”€â”€â”€ Post Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PostHeader extends StatelessWidget {
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
  final PostVisibility visibility;
  final VoidCallback? onTap;
  final bool isOwnPost;
  final VoidCallback? onDelete;
  final ValueChanged<PostVisibility>? onVisibilityChange;

  const _PostHeader({
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
    required this.visibility,
    this.onTap,
    this.isOwnPost = false,
    this.onDelete,
    this.onVisibilityChange,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            CachedAvatar(
              imageUrl: authorPhotoUrl,
              name: authorName,
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authorName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _TimeAgoText(dateTime: createdAt),
                      const SizedBox(width: 4),
                      Text(
                        'Â·',
                        style: TextStyle(
                          color: theme.colorScheme.outline,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        visibility == PostVisibility.public
                            ? Icons.public
                            : Icons.people,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isOwnPost && onDelete != null)
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  if (value == 'delete') onDelete!();
                  if (value == 'visibility') {
                    final newVisibility =
                        visibility == PostVisibility.public
                            ? PostVisibility.connections
                            : PostVisibility.public;
                    onVisibilityChange?.call(newVisibility);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'visibility',
                    child: Row(
                      children: [
                        Icon(
                          visibility == PostVisibility.public
                              ? Icons.people
                              : Icons.public,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(visibility == PostVisibility.public
                            ? 'Make Connections Only'
                            : 'Make Public'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: theme.colorScheme.error)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Time Ago â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TimeAgoText extends StatelessWidget {
  final DateTime dateTime;

  const _TimeAgoText({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    String text;
    if (difference.inMinutes < 1) {
      text = 'Just now';
    } else if (difference.inHours < 1) {
      text = '${difference.inMinutes}m';
    } else if (difference.inDays < 1) {
      text = '${difference.inHours}h';
    } else if (difference.inDays < 7) {
      text = '${difference.inDays}d';
    } else {
      text = '${(difference.inDays / 7).floor()}w';
    }

    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

// â”€â”€â”€ Single Media â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SingleMedia extends StatelessWidget {
  final MediaItem mediaItem;

  const _SingleMedia({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    if (mediaItem.type == PostMediaType.video) {
      return _VideoThumbnail(mediaItem: mediaItem);
    }

    return _PostImage(imageUrl: mediaItem.url);
  }
}

// â”€â”€â”€ Post Image â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PostImage extends StatelessWidget {
  final String imageUrl;

  const _PostImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 300,
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) => Container(
          height: 200,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.broken_image,
              size: 48,
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€ Video Thumbnail â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _VideoThumbnail extends StatefulWidget {
  final MediaItem mediaItem;

  const _VideoThumbnail({required this.mediaItem});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasError = false;
  bool _preloadStarted = false;

  /// Shared cache manager for post videos.
  static final _cacheManager = CacheManager(
    Config(
      'post_videos',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 50,
    ),
  );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;

    // Preload the video file into cache when >50% visible
    if (info.visibleFraction > 0.5 && !_preloadStarted) {
      _preloadStarted = true;
      _cacheManager.getFileFromCache(widget.mediaItem.url).then((fileInfo) {
        if (fileInfo == null) {
          _cacheManager.downloadFile(widget.mediaItem.url);
        }
      });
    }

    if (_controller == null || !_isInitialized) return;
    // Pause when less than 50% visible
    if (info.visibleFraction < 0.5 && _controller!.value.isPlaying) {
      _controller!.pause();
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  Future<void> _initializeAndPlay() async {
    if (_controller != null) {
      // Already initialized â€” toggle play/pause
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        setState(() => _isPlaying = false);
      } else {
        _controller!.play();
        setState(() => _isPlaying = true);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get video from cache (downloads if not cached)
      final file = await _cacheManager.getSingleFile(widget.mediaItem.url);

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      _controller!.addListener(_onVideoStateChanged);
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
        _controller!.play();
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _onVideoStateChanged() {
    if (!mounted || _controller == null) return;
    final isPlaying = _controller!.value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return VisibilityDetector(
      key: Key('video_${widget.mediaItem.url}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: _buildContent(theme),
    );
  }

  Widget _buildContent(ThemeData theme) {
    // If playing and initialized, show the video player
    if (_isInitialized && _controller != null) {
      return GestureDetector(
        onTap: _initializeAndPlay,
        child: Container(
          width: double.infinity,
          color: Colors.black,
          constraints: const BoxConstraints(maxHeight: 400),
          alignment: Alignment.center,
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller!),
                if (!_isPlaying)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                // Progress indicator at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    padding: const EdgeInsets.only(top: 4),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show thumbnail with play button overlay
    return GestureDetector(
      onTap: _hasError ? null : _initializeAndPlay,
      child: Container(
        height: 300,
        width: double.infinity,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Thumbnail image if available
            if (widget.mediaItem.thumbnailUrl != null)
              CachedNetworkImage(
                imageUrl: widget.mediaItem.thumbnailUrl!,
                width: double.infinity,
                height: 300,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),

            // Loading / Play / Error overlay
            if (_isLoading)
              const CircularProgressIndicator(color: Colors.white)
            else if (_hasError)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to load video',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€â”€ Media Carousel â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _MediaCarousel extends StatefulWidget {
  final List<MediaItem> mediaItems;

  const _MediaCarousel({required this.mediaItems});

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemCount = widget.mediaItems.length;

    return Column(
      children: [
        // Media pages
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: AspectRatio(
            aspectRatio: 1,
            child: PageView.builder(
              controller: _pageController,
              itemCount: itemCount,
              onPageChanged: (index) =>
                  setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final item = widget.mediaItems[index];
                if (item.type == PostMediaType.video) {
                  return _VideoThumbnail(mediaItem: item);
                }
                return _PostImage(imageUrl: item.url);
              },
            ),
          ),
        ),

        // Dot indicators
        if (itemCount > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(itemCount, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 8 : 6,
                  height: isActive ? 8 : 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
