import 'package:flutter/material.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/conversation.dart';

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
    // Use override values if provided (from ConnectionBloc cache), otherwise use conversation data
    final displayName = overrideDisplayName ?? otherParticipant?.displayName ?? 'Unknown';
    final photoUrl = overridePhotoUrl ?? otherParticipant?.photoUrl;
    final lastMessage = conversation.lastMessageText ?? 'No messages yet';
    final lastMessageTime = conversation.lastMessageAt;
    final unreadCount = conversation.getUnreadCount(currentUserId);
    final hasUnread = unreadCount > 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CachedAvatar(
            imageUrl: photoUrl,
            name: displayName,
            radius: 24,
          ),
          title: Text(
            displayName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              lastMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasUnread 
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMessageTime != null)
            Text(
              _formatTime(lastMessageTime),
              style: theme.textTheme.labelSmall?.copyWith(
                color: hasUnread 
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          if (hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 20),
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
          ],
        ],
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
}
