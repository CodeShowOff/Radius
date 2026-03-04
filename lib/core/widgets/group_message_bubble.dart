import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'linkified_text.dart';

/// Status of a group chat message.
///
/// Modeled after the v_chat_sdk VMessageEmitStatus pattern.
/// Groups don't need delivered/seen (no per-user read receipts in groups).
enum GroupMessageStatus {
  /// Message is pending (optimistic, not yet confirmed by server).
  pending,

  /// Message has been confirmed by server (arrived via Firestore stream).
  sent,

  /// Message failed to send.
  error,
}

/// A reusable message bubble for all group chat types (random, location, nearby).
///
/// Modeled after the v_chat_sdk VMessageItem pattern:
/// - Sender avatar + name for non-self messages (group context)
/// - System messages centered (like v_chat_sdk CenterItemHolder)
/// - Status indicator (clock for pending, check for sent, error icon)
/// - WhatsApp-style inline time
/// - Long-press actions (copy, delete, retry)
/// - Error overlay with "tap to retry" for failed messages
class GroupMessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool isSystemMessage;
  final bool showSenderInfo;
  final String? senderName;
  final String? senderPhotoUrl;
  final DateTime sentAt;
  final GroupMessageStatus status;
  final bool isDeleted;
  final VoidCallback? onSenderTap;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  const GroupMessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.isSystemMessage = false,
    this.showSenderInfo = false,
    this.senderName,
    this.senderPhotoUrl,
    required this.sentAt,
    this.status = GroupMessageStatus.sent,
    this.isDeleted = false,
    this.onSenderTap,
    this.onRetry,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // System messages (like v_chat_sdk CenterItemHolder)
    if (isSystemMessage) {
      return _SystemMessage(text: text);
    }

    // Deleted messages
    if (isDeleted) {
      return _DeletedBubble(isMe: isMe, sentAt: sentAt);
    }

    final theme = Theme.of(context);
    final maxWidth = MediaQuery.sizeOf(context).width * 0.75;
    final isError = status == GroupMessageStatus.error;

    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;

    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar for other users (like v_chat_sdk _getGroupUserAvatar)
          if (!isMe) ...[
            if (showSenderInfo)
              GestureDetector(
                onTap: onSenderTap,
                child: _SenderAvatar(
                  name: senderName,
                  photoUrl: senderPhotoUrl,
                ),
              )
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],

          // Message content column
          Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onLongPress: () => _showMessageActions(context),
                onTap: isError ? onRetry : null,
                child: IntrinsicWidth(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isError
                          ? bubbleColor.withValues(alpha: 0.6)
                          : bubbleColor,
                      borderRadius: borderRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sender name (like v_chat_sdk _getGroupUserTitle)
                        if (!isMe && showSenderInfo && senderName != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              senderName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isMe
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        // Text with inline time + status (WhatsApp style)
                        Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            LinkifiedText(
                              text: text,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isMe
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                                height: 1.3,
                              ) ?? const TextStyle(),
                              linkColor: isMe
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 1),
                              child: _MessageMeta(
                                sentAt: sentAt,
                                status: status,
                                isMe: isMe,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Error indicator row (like 1:1 chat MessageBubble)
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 14,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Failed to send. Tap to retry.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Show contextual actions on long-press (like v_chat_sdk message actions).
  void _showMessageActions(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Copy text
            if (text.isNotEmpty && !isDeleted)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),

            // Retry (for failed messages)
            if (status == GroupMessageStatus.error && onRetry != null)
              ListTile(
                leading: Icon(Icons.refresh, color: theme.colorScheme.primary),
                title: const Text('Retry'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRetry?.call();
                },
              ),

            // Delete (only for own messages)
            if (isMe && !isDeleted && onDelete != null)
              ListTile(
                leading:
                    Icon(Icons.delete_outline, color: theme.colorScheme.error),
                title: Text('Delete',
                    style: TextStyle(color: theme.colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Time + status indicator row (modeled after 1:1 chat _MessageMeta).
class _MessageMeta extends StatelessWidget {
  final DateTime sentAt;
  final GroupMessageStatus status;
  final bool isMe;

  const _MessageMeta({
    required this.sentAt,
    required this.status,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metaColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.5)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(sentAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: metaColor,
            fontSize: 11,
          ),
        ),
        // Status indicator (only for own messages)
        if (isMe) ...[
          const SizedBox(width: 3),
          _StatusIcon(status: status, color: metaColor),
        ],
      ],
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Status icon for group messages (like v_chat_sdk MessageStatusIcon).
class _StatusIcon extends StatelessWidget {
  final GroupMessageStatus status;
  final Color color;

  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case GroupMessageStatus.pending:
        return Icon(Icons.access_time, size: 14, color: color);
      case GroupMessageStatus.sent:
        return Icon(Icons.check, size: 14, color: color);
      case GroupMessageStatus.error:
        return Icon(Icons.error_outline, size: 14,
            color: Theme.of(context).colorScheme.error);
    }
  }
}

/// Sender avatar widget (like v_chat_sdk VCircleAvatar).
class _SenderAvatar extends StatelessWidget {
  final String? name;
  final String? photoUrl;

  const _SenderAvatar({this.name, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: 16,
      backgroundImage:
          photoUrl != null && photoUrl!.isNotEmpty
              ? NetworkImage(photoUrl!)
              : null,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: photoUrl == null || photoUrl!.isEmpty
          ? Text(
              (name ?? '?')[0].toUpperCase(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            )
          : null,
    );
  }
}

/// System message (centered, like v_chat_sdk CenterItemHolder).
class _SystemMessage extends StatelessWidget {
  final String text;

  const _SystemMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

/// Deleted message bubble.
class _DeletedBubble extends StatelessWidget {
  final bool isMe;
  final DateTime sentAt;

  const _DeletedBubble({required this.isMe, required this.sentAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 48 : 12,
            right: isMe ? 12 : 48,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Message deleted',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unread divider shown above the first unread message (WhatsApp style).
class GroupUnreadDivider extends StatelessWidget {
  final int count;

  const GroupUnreadDivider({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count <= 0
        ? 'Unread messages'
        : count == 1
            ? '1 unread message'
            : '$count unread messages';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state for group chats.
class GroupChatEmptyState extends StatelessWidget {
  const GroupChatEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
