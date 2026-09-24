import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Author header + location badge
          _NewsPostHeader(
            authorName: post.authorName,
            authorPhotoUrl: post.authorPhotoUrl,
            locationText: post.city.isNotEmpty ? '${post.city}, ${post.country}' : '',
            isOwnPost: isOwnPost,
            onDelete: onDelete,
          ),

          // 2. Media content (Edge-to-edge)
          if (post.hasMedia)
            post.hasMultipleMedia
                ? _MediaCarousel(mediaItems: post.mediaItems)
                : _SingleMedia(mediaItem: post.mediaItems.first),

          // 3. Interactive Action Bar (Like, Comment, Share)
          _ActionBar(onCommentTap: () => _openComments(context)),

          // 4. Caption, Likes Count, and Timestamp
          _PostCaption(
            post: post,
            onCommentTap: () => _openComments(context),
          ),
          
          const Divider(height: 1, thickness: 0.5),
        ],
      ),
    );
  }

  void _openComments(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    NewsCommentsBottomSheet.show(
      context: context,
      currentUserId: authState.user.id,
      currentUserName: authState.user.displayName ?? authState.user.username,
      currentUserPhotoUrl: authState.user.avatarUrl,
    );
  }
}

// ---------------------------------------------------------------------------
// Post header with author info, time, location badge, and menu
// ---------------------------------------------------------------------------
class _NewsPostHeader extends StatelessWidget {
  final String authorName;
  final String? authorPhotoUrl;
  final String locationText;
  final bool isOwnPost;
  final VoidCallback? onDelete;

  const _NewsPostHeader({
    required this.authorName,
    this.authorPhotoUrl,
    required this.locationText,
    this.isOwnPost = false,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CachedAvatar(
            imageUrl: authorPhotoUrl,
            name: authorName,
            radius: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (locationText.isNotEmpty)
                  Text(
                    locationText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
  final VoidCallback onCommentTap;
  
  const _ActionBar({required this.onCommentTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<NewsInteractionCubit, NewsInteractionState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              // Like button
              GestureDetector(
                onTap: () => _onLikeTap(context),
                child: Icon(
                  state.isLiked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                  size: 28,
                  color: state.isLiked ? Colors.red : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 16),
              // Comment button
              GestureDetector(
                onTap: onCommentTap,
                child: Icon(
                  CupertinoIcons.chat_bubble,
                  size: 28,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 16),
              // Share button
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Share will be available soon!')),
                  );
                },
                child: Icon(
                  CupertinoIcons.paperplane,
                  size: 28,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              // Bookmark placeholder
              Icon(
                CupertinoIcons.bookmark,
                size: 28,
                color: theme.colorScheme.onSurface,
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
  }}

// ---------------------------------------------------------------------------
// Caption, Likes, and Timestamp Below Action Bar
// ---------------------------------------------------------------------------
class _PostCaption extends StatelessWidget {
  final NewsPost post;
  final VoidCallback onCommentTap;

  const _PostCaption({required this.post, required this.onCommentTap});

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<NewsInteractionCubit, NewsInteractionState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Likes count
              if (state.likeCount > 0)
                Text(
                  '${_formatCount(state.likeCount)} likes',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              
              const SizedBox(height: 4),

              // 2. Author + Caption Text inline
              if (post.text != null && post.text!.isNotEmpty)
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium,
                    children: [
                      TextSpan(
                        text: '${post.authorName} ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: post.text!),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 4),

              // 3. View comments link
              if (state.commentCount > 0)
                GestureDetector(
                  onTap: onCommentTap,
                  child: Text(
                    'View all ${_formatCount(state.commentCount)} comments',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              const SizedBox(height: 4),

              // 4. Timestamp
              _TimeAgoText(dateTime: post.createdAt),
              
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Time ago formatting
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
      text = 'JUST NOW';
    } else if (difference.inHours < 1) {
      text = '${difference.inMinutes} MINUTES AGO';
    } else if (difference.inDays < 1) {
      text = '${difference.inHours} HOURS AGO';
    } else if (difference.inDays < 7) {
      text = '${difference.inDays} DAYS AGO';
    } else {
      text = '${(difference.inDays / 7).floor()} WEEKS AGO';
    }

    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 10,
        fontWeight: FontWeight.w500,
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

  static final _imageCacheManager = CacheManager(
    Config(
      'news_images',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 150,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 500),
      child: CachedNetworkImage(
        cacheManager: _imageCacheManager,
        imageUrl: imageUrl,
        width: double.infinity,
        fit: BoxFit.contain,
        placeholder: (context, url) => Container(
          height: 350,
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        errorWidget: (context, url, error) => Container(
          height: 350,
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

    // Video is initialized â€” show the player
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
                fit: BoxFit.contain,
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
