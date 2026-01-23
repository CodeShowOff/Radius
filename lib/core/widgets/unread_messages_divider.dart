import 'package:flutter/material.dart';

/// A divider widget that indicates the start of unread messages in a chat.
///
/// This widget displays a horizontal line with "Unread messages" text,
/// styled to stand out and help users identify where new messages begin.
///
/// Usage:
/// ```dart
/// // In a ListView with messages
/// if (message.id == firstUnreadMessageId) {
///   return Column(
///     children: [
///       const UnreadMessagesDivider(),
///       MessageBubble(message: message),
///     ],
///   );
/// }
/// ```
class UnreadMessagesDivider extends StatelessWidget {
  /// Optional custom label text.
  final String? label;

  /// Whether to animate the divider appearance.
  final bool animate;

  const UnreadMessagesDivider({
    super.key,
    this.label,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Widget divider = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0),
                    colorScheme.primary.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 14,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  label ?? 'Unread messages',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.5),
                    colorScheme.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!animate) return divider;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scaleX: value,
            child: child,
          ),
        );
      },
      child: divider,
    );
  }
}

/// A simpler, compact version of the unread divider for group chats.
class UnreadMessagesDividerCompact extends StatelessWidget {
  /// Optional unread count to display in the label.
  /// If null, displays generic "Unread messages" text.
  final int? unreadCount;

  const UnreadMessagesDividerCompact({
    super.key,
    this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String label = unreadCount == null
        ? 'Unread messages'
        : unreadCount == 1
            ? '1 unread message'
            : '$unreadCount unread messages';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
