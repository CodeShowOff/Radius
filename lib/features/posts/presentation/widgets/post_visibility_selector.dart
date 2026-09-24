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

    return Row(
      children: [
        Icon(
          visibility == PostVisibility.public
              ? Icons.public
              : Icons.people,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            visibility == PostVisibility.public
                ? 'Public'
                : 'Connections Only',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        SegmentedButton<PostVisibility>(
          segments: const [
            ButtonSegment(
              value: PostVisibility.public,
              icon: Icon(Icons.public, size: 18),
              label: Text('Public'),
            ),
            ButtonSegment(
              value: PostVisibility.connections,
              icon: Icon(Icons.people, size: 18),
              label: Text('Connections'),
            ),
          ],
          selected: {visibility},
          onSelectionChanged: (value) => onChanged(value.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: WidgetStatePropertyAll(
              theme.textTheme.labelSmall,
            ),
          ),
        ),
      ],
    );
  }
}
