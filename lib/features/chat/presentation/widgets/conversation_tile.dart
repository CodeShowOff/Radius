import 'package:flutter/material.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../domain/entities/conversation.dart';

/// WhatsApp-style conversation tile, modeled after v_chat_sdk's VRoomItem.
///
/// Layout (matching VRoomItem):
/// ┌─────────────────────────────────────────────────┐
/// │  [Avatar]  Title               Mute  Time       │
/// │            ✓✓ Last message / Typing…   [Badge]  │
/// └─────────────────────────────────────────────────┘
///
/// Features:
/// - Unread badge (green circle like v_chat_sdk ChatUnReadWidget)
/// - Mute icon when conversation is muted
/// - Message status icon (sent by me → ✓✓)
/// - Typing indicator (green text)
/// - Bold last message when unread (v_chat_sdk RoomItemMsg isBold)
/// - Smart time formatting (today/yesterday/day/date)
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? overrideDisplayName;
  final String? overridePhotoUrl;
  final bool isTyping;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
    this.onLongPress,
    this.overrideDisplayName,
    this.overridePhotoUrl,
    this.isTyping = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherParticipant = conversation.getOtherParticipantInfo(currentUserId);
    final displayName = overrideDisplayName ??
        otherParticipant?.displayName ??
        'Unknown';
    final photoUrl = overridePhotoUrl ?? otherParticipant?.photoUrl;
    final lastMessage = conversation.lastMessageText;
    final lastMessageTime = conversation.lastMessageAt;
    final unreadCount = conversation.getUnreadCount(currentUserId);
    final hasUnread = unreadCount > 0;
    final isMuted = conversation.isMutedBy(currentUserId);
    final isMeSender = conversation.lastMessageSenderId == currentUserId;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // ── Avatar ──
            CachedAvatar(
              imageUrl: photoUrl,
              name: displayName,
              radius: 26,
            ),
            const SizedBox(width: 12),

            // ── Content ──
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ─── TOP ROW: Title + Time ───
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastMessageTime != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(lastMessageTime),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hasUnread
                                ? const Color(0xFF25D366)
                                : theme.colorScheme.outline,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // ─── BOTTOM ROW: Last message / Typing + Mute + Badge ───
                  Row(
                    children: [
                      // Typing indicator or last message
                      Expanded(
                        child: isTyping
                            ? Text(
                                'typing…',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.green,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : Row(
                                children: [
                                  // Message status icon for sender's own messages
                                  if (isMeSender && lastMessage != null) ...[
                                    Icon(
                                      Icons.done_all,
                                      size: 16,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(
                                      lastMessage ?? 'No messages yet',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: hasUnread
                                            ? theme.colorScheme.onSurface
                                            : theme.colorScheme.outline,
                                        fontWeight: hasUnread
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                      ),

                      // Mute icon (v_chat_sdk ChatMuteWidget pattern)
                      if (isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.notifications_off,
                          size: 16,
                          color: theme.colorScheme.outline,
                        ),
                      ],

                      // Unread badge (v_chat_sdk ChatUnReadWidget pattern — green circle)
                      if (hasUnread) ...[
                        const SizedBox(width: 6),
                        Container(
                          height: 22,
                          constraints: const BoxConstraints(minWidth: 22),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366), // WhatsApp green
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
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
