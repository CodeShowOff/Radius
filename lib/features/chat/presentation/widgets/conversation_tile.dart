import 'package:flutter/material.dart';

import '../../domain/entities/conversation.dart';

/// Shared widget for displaying a conversation tile.
/// Used in both Conversations screen and Home page preview.
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherParticipant = conversation.getOtherParticipantInfo(currentUserId);
    final unreadCount = conversation.getUnreadCount(currentUserId);
    final displayName = otherParticipant?.displayName ?? 'Unknown';
    final photoUrl = otherParticipant?.photoUrl;
    final lastMessage = conversation.lastMessageText ?? 'No messages yet';
    final lastMessageTime = conversation.lastMessageAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: photoUrl == null
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              )
            : null,
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
              child: Icon(
                Icons.done_all,
                size: 14,
                color: theme.colorScheme.outline,
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    child: Center(
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          : null,
      onTap: onTap,
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
}
