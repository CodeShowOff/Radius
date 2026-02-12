import 'package:flutter/material.dart';

import '../../domain/entities/message.dart';
import '../../domain/entities/chat_config.dart';
import 'message_bubble.dart';

/// Shared messages list widget for chat conversations.
///
/// Displays messages with appropriate styling based on [config].
class SharedMessagesList extends StatelessWidget {
  /// Messages to display.
  final List<Message> messages;

  /// ID of the current user.
  final String currentUserId;

  /// Display configuration (anonymous vs identified).
  final ChatConfig config;

  /// Whether the other user is typing.
  final bool isTyping;

  /// Whether there are more messages to load.
  final bool hasMore;

  /// Scroll controller for pagination.
  final ScrollController scrollController;

  /// Whether messages are currently loading.
  final bool isLoading;

  /// Optional name of the other user (for identified mode).
  final String? otherUserName;

  /// Optional photo URL of the other user (for identified mode).
  final String? otherUserPhotoUrl;

  /// Callback for retrying a failed message.
  final void Function(Message message)? onRetryMessage;

  /// Callback for removing a failed message.
  final void Function(Message message)? onRemoveFailedMessage;

  const SharedMessagesList({
    super.key,
    required this.messages,
    required this.currentUserId,
    required this.config,
    this.isTyping = false,
    this.hasMore = false,
    required this.scrollController,
    this.isLoading = false,
    this.otherUserName,
    this.otherUserPhotoUrl,
    this.onRetryMessage,
    this.onRemoveFailedMessage,
  });

  @override
  Widget build(BuildContext context) {
    // Only show empty state if not loading and no messages
    if (messages.isEmpty && !isTyping && !isLoading) {
      return _buildEmptyState(context);
    }

    // If loading with no messages yet, show nothing (parent handles spinner)
    if (messages.isEmpty && isLoading) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      controller: scrollController,
      reverse: true, // Most recent at bottom
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (hasMore ? 1 : 0) + (isTyping ? 1 : 0),
      // Performance optimizations
      cacheExtent: 500, // Cache more items off-screen
      itemBuilder: (context, index) {
        // Typing indicator at index 0 (bottom of reversed list)
        if (config.showTypingIndicator && isTyping && index == 0) {
          return _buildTypingIndicator(context);
        }

        // Adjust index for typing indicator
        final adjustedIndex =
            (config.showTypingIndicator && isTyping) ? index - 1 : index;

        // Loading indicator at the top (end of reversed list)
        if (hasMore && adjustedIndex == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final message = messages[adjustedIndex];
        final isMe = message.senderId == currentUserId;

        // Check if we should show tail (grouping messages)
        final showTail = _shouldShowTail(adjustedIndex);

        // Check if we should show date separator
        final showDate = _shouldShowDate(adjustedIndex);

        // Wrap in RepaintBoundary for better scrolling performance
        return RepaintBoundary(
          child: Column(
            children: [
              if (showDate) _buildDateSeparator(context, message.sentAt),
              _buildMessageBubble(
                context,
                message,
                isMe,
                showTail,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final isAnonymous = config.displayMode == ChatDisplayMode.anonymous;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isAnonymous ? 'Start chatting!' : 'No messages yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAnonymous
                  ? 'Say hi to your mystery partner.\nTry to figure out who they are!'
                  : 'Say hello! 👋',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final isAnonymous = config.displayMode == ChatDisplayMode.anonymous;

    // Pre-compute avatar background color
    final anonymousAvatarColor = theme.colorScheme.secondary;
    final bubbleColor = theme.colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Avatar for identified mode
          if (!isAnonymous) ...[
            CircleAvatar(
              radius: 16,
              backgroundImage: otherUserPhotoUrl != null
                  ? NetworkImage(otherUserPhotoUrl!)
                  : null,
              child: otherUserPhotoUrl == null
                  ? Text(
                      (otherUserName?.isNotEmpty == true)
                          ? otherUserName![0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          // Anonymous avatar
          if (isAnonymous) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: anonymousAvatarColor,
              child: const Text(
                '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _AnimatedTypingDots(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(BuildContext context, DateTime date) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == today) {
      dateText = 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      dateText = 'Yesterday';
    } else if (messageDate.isAfter(today.subtract(const Duration(days: 7)))) {
      // Within last week, show day name
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      dateText = days[messageDate.weekday - 1];
    } else {
      // Older than a week, show date
      dateText = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dateText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Message message,
    bool isMe,
    bool showTail,
  ) {
    final isAnonymous = config.displayMode == ChatDisplayMode.anonymous;

    // Handle system messages (centered, special styling)
    if (message.senderId == 'system') {
      return _buildSystemMessage(context, message);
    }

    // For identified mode, use the existing MessageBubble widget
    if (!isAnonymous) {
      return MessageBubble(
        message: message,
        isMe: isMe,
        showTail: showTail,
      );
    }

    // For anonymous mode, use simplified bubble
    return _buildAnonymousMessageBubble(context, message, isMe, showTail);
  }

  /// Builds a system message
  Widget _buildSystemMessage(BuildContext context, Message message) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildAnonymousMessageBubble(
    BuildContext context,
    Message message,
    bool isMe,
    bool showTail,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe && showTail) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.secondary,
                  child: const Text(
                    '?',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (!isMe && !showTail) const SizedBox(width: 40),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe || !showTail ? 16 : 4),
                      bottomRight: Radius.circular(!isMe || !showTail ? 16 : 4),
                    ),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        message.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: isMe
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Time and status indicator
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${message.sentAt.hour.toString().padLeft(2, '0')}:${message.sentAt.minute.toString().padLeft(2, '0')}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isMe
                                    ? theme.colorScheme.onPrimary
                                        .withValues(alpha: 0.7)
                                    : theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _shouldShowTail(int index) {
    if (index == 0) return true;

    final currentMessage = messages[index];
    final previousMessage = messages[index - 1];

    // Different sender
    if (currentMessage.senderId != previousMessage.senderId) return true;

    // Time gap > 1 minute
    final timeDiff = previousMessage.sentAt.difference(currentMessage.sentAt);
    if (timeDiff.inMinutes > 1) return true;

    return false;
  }

  bool _shouldShowDate(int index) {
    if (index == messages.length - 1) return true;

    final currentMessage = messages[index];
    final nextMessage = messages[index + 1];

    final currentDate = DateTime(
      currentMessage.sentAt.year,
      currentMessage.sentAt.month,
      currentMessage.sentAt.day,
    );
    final nextDate = DateTime(
      nextMessage.sentAt.year,
      nextMessage.sentAt.month,
      nextMessage.sentAt.day,
    );

    return currentDate != nextDate;
  }
}

/// Optimized animated typing dots widget.
///
/// Uses a single AnimationController instead of multiple TweenAnimationBuilders
/// for better performance.
class _AnimatedTypingDots extends StatefulWidget {
  final Color color;

  const _AnimatedTypingDots({required this.color});

  @override
  State<_AnimatedTypingDots> createState() => _AnimatedTypingDotsState();
}

class _AnimatedTypingDotsState extends State<_AnimatedTypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(0),
            const SizedBox(width: 4),
            _buildDot(0.33),
            const SizedBox(width: 4),
            _buildDot(0.66),
          ],
        );
      },
    );
  }

  Widget _buildDot(double offset) {
    final animValue = (_controller.value + offset) % 1.0;
    final opacity = animValue < 0.5
        ? 0.3 + (0.7 * (animValue * 2))
        : 0.3 + (0.7 * (2 - animValue * 2));

    return Opacity(
      opacity: opacity,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
