import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../domain/entities/news_post.dart';
import '../../domain/repositories/i_news_post_repository.dart';

/// Detail page for viewing a single local news post.
///
/// Shows full media viewer, full text, author info, location, and
/// placeholder sections for likes/comments (wired in Phase 6).
class NewsPostDetailPage extends StatelessWidget {
  final String postId;

  /// Optionally pass an already-loaded post to avoid a re-fetch.
  final NewsPost? initialPost;

  const NewsPostDetailPage({
    super.key,
    required this.postId,
    this.initialPost,
  });

  @override
  Widget build(BuildContext context) {
    // If we have the post already, show it directly.
    // Otherwise, stream real-time updates from the repository.
    if (initialPost != null) {
      return _DetailScaffold(post: initialPost!);
    }

    return StreamBuilder<NewsPost?>(
      stream: context.read<INewsPostRepository>().postStream(postId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Text('Error loading post: ${snapshot.error}'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final post = snapshot.data;

        if (post == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Post not found')),
          );
        }

        return _DetailScaffold(post: post);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Main scaffold for the detail view
// ---------------------------------------------------------------------------
class _DetailScaffold extends StatelessWidget {
  final NewsPost post;

  const _DetailScaffold({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('News Post'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author header
            _DetailHeader(post: post),

            const SizedBox(height: 12),

            // Media
            if (post.hasMedia)
              post.hasMultipleMedia
                  ? _DetailMediaCarousel(mediaItems: post.mediaItems)
                  : _DetailSingleMedia(mediaItem: post.mediaItems.first),

            // Text content
            if (post.text != null && post.text!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  post.text!,
                  style: theme.textTheme.bodyLarge,
                ),
              ),

            // Like / Comment summary
            _InteractionSummary(
              likeCount: post.likeCount,
              commentCount: post.commentCount,
            ),

            const Divider(height: 1),

            // Placeholder for comments section (Phase 6)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Comments',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            if (post.commentCount == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text(
                  'No comments yet. Be the first to comment!',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

            // Bottom padding for safe area
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail header
// ---------------------------------------------------------------------------
class _DetailHeader extends StatelessWidget {
  final NewsPost post;

  const _DetailHeader({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          CachedAvatar(
            imageUrl: post.authorPhotoUrl,
            name: post.authorName,
            radius: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.authorName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDateTime(post.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    // Simple date format for older posts
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}

// ---------------------------------------------------------------------------
// Interaction summary (likes + comments count)
// ---------------------------------------------------------------------------
class _InteractionSummary extends StatelessWidget {
  final int likeCount;
  final int commentCount;

  const _InteractionSummary({
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          if (likeCount > 0) ...[
            Icon(Icons.favorite, size: 18, color: Colors.red.shade400),
            const SizedBox(width: 4),
            Text(
              '$likeCount ${likeCount == 1 ? 'like' : 'likes'}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (likeCount > 0 && commentCount > 0)
            const SizedBox(width: 16),
          if (commentCount > 0) ...[
            Icon(Icons.chat_bubble_outline,
                size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              '$commentCount ${commentCount == 1 ? 'comment' : 'comments'}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single media (full-width image or video thumbnail)
// ---------------------------------------------------------------------------
class _DetailSingleMedia extends StatelessWidget {
  final MediaItem mediaItem;

  const _DetailSingleMedia({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    if (mediaItem.type == PostMediaType.video) {
      return _DetailVideoThumbnail(mediaItem: mediaItem);
    }
    return _DetailImage(imageUrl: mediaItem.url);
  }
}

// ---------------------------------------------------------------------------
// Full-width image
// ---------------------------------------------------------------------------
class _DetailImage extends StatelessWidget {
  final String imageUrl;

  const _DetailImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CachedNetworkImage(
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
    );
  }
}

// ---------------------------------------------------------------------------
// Video thumbnail with play icon
// ---------------------------------------------------------------------------
class _DetailVideoThumbnail extends StatelessWidget {
  final MediaItem mediaItem;

  const _DetailVideoThumbnail({required this.mediaItem});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnailUrl = mediaItem.thumbnailUrl;

    return Stack(
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
              height: 300,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
          )
        else
          Container(
            height: 300,
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest,
          ),
        // Play button overlay
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow,
            color: Colors.white,
            size: 40,
          ),
        ),
        // Duration badge
        if (mediaItem.durationMs != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(mediaItem.durationMs!),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
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
// Media carousel for multiple items
// ---------------------------------------------------------------------------
class _DetailMediaCarousel extends StatefulWidget {
  final List<MediaItem> mediaItems;

  const _DetailMediaCarousel({required this.mediaItems});

  @override
  State<_DetailMediaCarousel> createState() => _DetailMediaCarouselState();
}

class _DetailMediaCarouselState extends State<_DetailMediaCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        SizedBox(
          height: 400,
          child: PageView.builder(
            itemCount: widget.mediaItems.length,
            onPageChanged: (page) {
              setState(() => _currentPage = page);
            },
            itemBuilder: (context, index) {
              final item = widget.mediaItems[index];
              if (item.type == PostMediaType.video) {
                return _DetailVideoThumbnail(mediaItem: item);
              }
              return _DetailImage(imageUrl: item.url);
            },
          ),
        ),
        const SizedBox(height: 8),
        // Page indicator
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${_currentPage + 1} / ${widget.mediaItems.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
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
