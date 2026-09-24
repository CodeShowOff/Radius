import 'package:flutter/material.dart';

import '../../domain/entities/post.dart';

/// A toggle widget for selecting post visibility (public or connections-only).
class PostVisibilitySelector extends StatelessWidget {
  final PostVisibility visibility;
  final ValueChanged<PostVisibility> onChanged;

  const PostVisibilitySelector({
    super.key,
    required this.visibility,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPublic = visibility == PostVisibility.public;

    return PopupMenuButton<PostVisibility>(
      initialValue: visibility,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      offset: const Offset(0, 32),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: PostVisibility.public,
          child: Row(
            children: [
              Icon(Icons.public, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Public'),
            ],
          ),
        ),
        PopupMenuItem(
          value: PostVisibility.connections,
          child: Row(
            children: [
              Icon(Icons.people, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Text('Connections Only'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPublic ? Icons.public : Icons.people,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              isPublic ? 'Public' : 'Connections',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
