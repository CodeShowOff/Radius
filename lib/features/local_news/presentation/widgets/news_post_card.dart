import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/news_post.dart';

class NewsPostCard extends StatelessWidget {
  final NewsPost post;
  final bool isOwnPost;
  final VoidCallback? onDelete;
  final VoidCallback? onLikeTap;
  final VoidCallback? onCommentTap;

  const NewsPostCard({
    super.key,
    required this.post,
    this.isOwnPost = false,
    this.onDelete,
    this.onLikeTap,
    this.onCommentTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CachedAvatar(
              imageUrl: post.authorPhotoUrl,
              name: post.authorName,
              radius: 20,
            ),
            title: Text(post.authorName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${post.city}, ${post.country}', style: TextStyle(color: theme.colorScheme.outline, fontSize: 12)),
            trailing: isOwnPost && onDelete != null
                ? IconButton(icon: const Icon(Icons.more_vert), onPressed: onDelete)
                : null,
          ),
          if ((post.text ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text((post.text ?? ''), style: theme.textTheme.bodyMedium),
            ),
          if (post.mediaItems.map((m) => m.url).toList().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 300,
                child: PageView.builder(
                  itemCount: post.mediaItems.map((m) => m.url).toList().length,
                  itemBuilder: (context, index) {
                    return CachedNetworkImage(
                      imageUrl: post.mediaItems.map((m) => m.url).toList()[index],
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: theme.colorScheme.surfaceContainerHighest),
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onLikeTap,
                  child: Row(
                    children: [
                      Icon(Icons.favorite_border, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('${post.likeCount}'),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: onCommentTap,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('${post.commentCount}'),
                    ],
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
