import 'package:flutter/material.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// Shared widget for displaying a conversation tile.
/// Used in both Conversations screen and Home page preview.
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;
  final String? overrideDisplayName;
  final String? overridePhotoUrl;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
    this.overrideDisplayName,
    this.overridePhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherParticipant = conversation.getOtherParticipantInfo(currentUserId);
    final unreadCount = conversation.getUnreadCount(currentUserId);
    // Use override values if provided (from ConnectionBloc cache), otherwise use conversation data
    final displayName = overrideDisplayName ?? otherParticipant?.displayName ?? 'Unknown';
    final photoUrl = overridePhotoUrl ?? otherParticipant?.photoUrl;
    final lastMessage = conversation.lastMessageText ?? 'No messages yet';
    final lastMessageTime = conversation.lastMessageAt;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
        enabled: false, // Disable ListTile's own tap handling
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CachedAvatar(
        imageUrl: photoUrl,
        name: displayName,
        radius: 24,
      ),
      title: Text(
        displayName,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (conversation.lastMessageSenderId == currentUserId)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildStatusIcon(
                conversation.lastMessageStatus ?? MessageStatus.sent,
                theme,
              ),
            ),
          Expanded(
            child: Text(
              lastMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: unreadCount > 0
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outline,
                fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: lastMessageTime != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(lastMessageTime),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: unreadCount > 0
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                      maxWidth: 50,
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
            )
          : null,
      ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.difference(time).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }

  Widget _buildStatusIcon(MessageStatus status, ThemeData theme) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox.shrink(); // Hidden while sending
      case MessageStatus.sent:
        return Icon(
          Icons.done,
          size: 14,
          color: theme.colorScheme.outline,
        );
      case MessageStatus.delivered:
        return Icon(
          Icons.done_all,
          size: 14,
          color: theme.colorScheme.outline,
        );
      case MessageStatus.read:
        return const Icon(
          Icons.done_all,
          size: 14,
          color: Colors.blue,
        );
      case MessageStatus.failed:
        return Icon(
          Icons.error,
          size: 14,
          color: theme.colorScheme.error,
        );
    }
  }
}
