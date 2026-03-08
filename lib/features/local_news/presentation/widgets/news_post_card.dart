import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';

/// Card widget displaying a single local news post in the feed.
///
/// Shows author info, location badge, text, media carousel, and
/// read-only like/comment counts. Interactive engagement is added in Phase 6.
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
              locationLabel: post.locationLabel,
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

            // Like / Comment counts (read-only in Phase 4)
            _ActionBar(
              likeCount: post.likeCount,
              commentCount: post.commentCount,
            ),
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
  final String locationLabel;
  final bool isOwnPost;
  final VoidCallback? onDelete;

  const _NewsPostHeader({
    required this.authorName,
    this.authorPhotoUrl,
    required this.createdAt,
    required this.locationLabel,
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
                Row(
                  children: [
                    _TimeAgoText(dateTime: createdAt),
                    const SizedBox(width: 6),
                    Text(
                      '·',
                      style: TextStyle(
                        color: theme.colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.location_on,
                      size: 13,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        locationLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
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
// Read-only action bar with like/comment counts
// ---------------------------------------------------------------------------
class _ActionBar extends StatelessWidget {
  final int likeCount;
  final int commentCount;

  const _ActionBar({
    required this.likeCount,
    required this.commentCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (likeCount == 0 && commentCount == 0) {
      return const SizedBox(height: 8);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          if (likeCount > 0) ...[
            Icon(
              Icons.favorite,
              size: 16,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              _formatCount(likeCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
          if (likeCount > 0 && commentCount > 0)
            const SizedBox(width: 16),
          if (commentCount > 0) ...[
            Icon(
              Icons.chat_bubble_outline,
              size: 16,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 4),
            Text(
              _formatCount(commentCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
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
// Video thumbnail with play icon overlay
// ---------------------------------------------------------------------------
class _VideoThumbnailView extends StatelessWidget {
  final MediaItem mediaItem;

  const _VideoThumbnailView({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnailUrl = mediaItem.thumbnailUrl;

    return ConstrainedBox(
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
                child: const Center(child: CircularProgressIndicator()),
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
          // Play button overlay
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
          if (mediaItem.durationMs != null)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(mediaItem.durationMs!),
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
