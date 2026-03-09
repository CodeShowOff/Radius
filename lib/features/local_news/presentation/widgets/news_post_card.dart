import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';
import '../bloc/news_interaction_cubit.dart';
import 'news_comments_bottom_sheet.dart';

/// Card widget displaying a single local news post in the feed.
///
/// Shows author info, location badge, text, media carousel, and
/// interactive like/comment buttons.
class NewsPostCard extends StatelessWidget {
  final NewsPost post;
  final bool isOwnPost;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const NewsPostCard({
    super.key,
    required this.post,
    this.isOwnPost = false,
    this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author header + location badge
            _NewsPostHeader(
              authorName: post.authorName,
              authorPhotoUrl: post.authorPhotoUrl,
              createdAt: post.createdAt,
              isOwnPost: isOwnPost,
              onDelete: onDelete,
            ),

            // Media content
            if (post.hasMedia)
              post.hasMultipleMedia
                  ? _MediaCarousel(mediaItems: post.mediaItems)
                  : _SingleMedia(mediaItem: post.mediaItems.first),

            // Text content
            if (post.text != null && post.text!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  post.text!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Like / Comment actions
            const _ActionBar(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Post header with author info, time, location badge, and menu
// ---------------------------------------------------------------------------
class _NewsPostHeader extends StatelessWidget {
  final String authorName;
  final String? authorPhotoUrl;
  final DateTime createdAt;
  final bool isOwnPost;
  final VoidCallback? onDelete;

  const _NewsPostHeader({
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
    this.isOwnPost = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
                _TimeAgoText(dateTime: createdAt),
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
              },
              itemBuilder: (_) => [
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
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive action bar with like/comment buttons
// ---------------------------------------------------------------------------
class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<NewsInteractionCubit, NewsInteractionState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(
            children: [
              // Like button
              InkWell(
                onTap: () => _onLikeTap(context),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.isLiked
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: 22,
                        color: state.isLiked
                            ? Colors.red
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      if (state.likeCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          _formatCount(state.likeCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Comment button
              InkWell(
                onTap: () => _onCommentTap(context),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      if (state.commentCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          _formatCount(state.commentCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Share button
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Share will be available soon!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Icon(
                    Icons.share_outlined,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// ---------------------------------------------------------------------------
// Time ago
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Single media item (image or video thumbnail)
// ---------------------------------------------------------------------------
class _SingleMedia extends StatelessWidget {
  final MediaItem mediaItem;

  const _SingleMedia({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    if (mediaItem.type == PostMediaType.video) {
      return _VideoThumbnailView(mediaItem: mediaItem);
    }
    return _NewsImage(imageUrl: mediaItem.url);
  }
}

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------
class _NewsImage extends StatelessWidget {
  final String imageUrl;

  const _NewsImage({required this.imageUrl});

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

// ---------------------------------------------------------------------------
// Video player with thumbnail fallback
// ---------------------------------------------------------------------------
class _VideoThumbnailView extends StatefulWidget {
  final MediaItem mediaItem;

  const _VideoThumbnailView({required this.mediaItem});

  @override
  State<_VideoThumbnailView> createState() => _VideoThumbnailViewState();
}

class _VideoThumbnailViewState extends State<_VideoThumbnailView> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasError = false;

  static final _cacheManager = CacheManager(
    Config(
      'news_videos',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 50,
    ),
  );

  @override
  void dispose() {
    _controller?.removeListener(_onVideoStateChanged);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeAndPlay() async {
    if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        _controller!.play();
        if (mounted) setState(() => _isPlaying = true);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final file =
          await _cacheManager.getSingleFile(widget.mediaItem.url);

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
    } catch (_) {
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

    // Video is initialized — show the player
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

    // Thumbnail with play button
    final thumbnailUrl = widget.mediaItem.thumbnailUrl;
    return GestureDetector(
      onTap: _hasError ? null : _initializeAndPlay,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumbnailUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 300,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child:
                      const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 250,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              )
            else
              Container(
                height: 250,
                width: double.infinity,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            // Loading / Play / Error overlay
            if (_isLoading)
              const CircularProgressIndicator(color: Colors.white)
            else if (_hasError)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 8),
                  Text('Failed to load video',
                      style:
                          TextStyle(color: theme.colorScheme.error)),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            // Duration badge
            if (widget.mediaItem.durationMs != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(widget.mediaItem.durationMs!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Media carousel for multi-media posts
// ---------------------------------------------------------------------------
class _MediaCarousel extends StatefulWidget {
  final List<MediaItem> mediaItems;

  const _MediaCarousel({required this.mediaItems});

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        SizedBox(
          height: 350,
          child: PageView.builder(
            itemCount: widget.mediaItems.length,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
            },
            itemBuilder: (context, index) {
              final item = widget.mediaItems[index];
              if (item.type == PostMediaType.video) {
                return _VideoThumbnailView(mediaItem: item);
              }
              return _NewsImage(imageUrl: item.url);
            },
          ),
        ),
        const SizedBox(height: 8),
        // Dot indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.mediaItems.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: index == _currentPage ? 8 : 6,
              height: index == _currentPage ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index == _currentPage
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
