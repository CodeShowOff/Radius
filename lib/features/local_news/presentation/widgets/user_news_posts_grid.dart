import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../posts/domain/entities/media_item.dart';
import '../../data/services/news_post_service.dart';
import '../../domain/entities/news_post.dart';

/// Grid view of a user's local news posts (Instagram-style thumbnails).
///
/// Fetches posts directly from [NewsPostService] by author ID.
/// Shows media thumbnails in a 3-column grid, or text for text-only posts.
class UserNewsPostsGrid extends StatefulWidget {
  final String userId;

  const UserNewsPostsGrid({super.key, required this.userId});

  @override
  State<UserNewsPostsGrid> createState() => _UserNewsPostsGridState();
}

class _UserNewsPostsGridState extends State<UserNewsPostsGrid>
    with AutomaticKeepAliveClientMixin {
  final _service = getIt<NewsPostService>();
  List<NewsPost> _posts = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await _service.getPostsByAuthor(
        authorId: widget.userId,
      );
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48,
                  color: theme.colorScheme.error),
              const SizedBox(height: 8),
              const Text('Failed to load news posts',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  _loadPosts();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.newspaper_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'No News Posts Yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final post = _posts[index];
              return GestureDetector(
                onTap: () => context.push(
                  Routes.localNewsPostWith(post.id),
                ),
                child: _NewsGridTile(post: post),
              );
            },
            childCount: _posts.length,
          ),
        ),
      ],
    );
  }
}

/// Single tile in the news posts grid.
class _NewsGridTile extends StatelessWidget {
  final NewsPost post;

  const _NewsGridTile({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!post.hasMedia) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              post.text ?? '',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final firstMedia = post.mediaItems.first;

    if (firstMedia.type == PostMediaType.video) {
      final thumbUrl = firstMedia.thumbnailUrl ?? firstMedia.url;
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: thumbUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            errorWidget: (_, __, ___) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
          const Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.videocam,
              color: Colors.white,
              size: 18,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: firstMedia.url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
        if (post.hasMultipleMedia)
          const Positioned(
            top: 4,
            right: 4,
            child: Icon(
              Icons.collections,
              color: Colors.white,
              size: 18,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
      ],
    );
  }
}
