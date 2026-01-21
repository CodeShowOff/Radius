import 'package:flutter/material.dart';

import '../../domain/entities/message.dart';
import '../../domain/entities/chat_config.dart';
import 'message_bubble.dart';

/// Shared messages list widget that works for both Connections and Guess Me.
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
      itemBuilder: (context, index) {
        // Typing indicator at index 0 (bottom of reversed list)
        if (config.showTypingIndicator && isTyping && index == 0) {
          return _buildTypingIndicator(context);
        }

        // Adjust index for typing indicator
        final adjustedIndex = (config.showTypingIndicator && isTyping) ? index - 1 : index;

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

        return Column(
          children: [
            if (showDate) _buildDateSeparator(context, message.sentAt),
            _buildMessageBubble(
              context,
              message,
              isMe,
              showTail,
            ),
          ],
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(theme, 0),
                const SizedBox(width: 4),
                _buildTypingDot(theme, 200),
                const SizedBox(width: 4),
                _buildTypingDot(theme, 400),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(ThemeData theme, int delay) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: 0.3 + (0.7 * value),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
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
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
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
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
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
    if (message.senderId == 'system' || message.senderId == 'guesscheck_system') {
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

  /// Builds a system message (game events, guess checks, etc.)
  Widget _buildSystemMessage(BuildContext context, Message message) {
    final theme = Theme.of(context);
    final isGuessCheck = message.senderId == 'guesscheck_system';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isGuessCheck
                ? Colors.orange.withValues(alpha: 0.2)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
            border: isGuessCheck ? Border.all(color: Colors.orange, width: 1.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isGuessCheck) ...[
                const Icon(Icons.psychology, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  message.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: isGuessCheck ? FontWeight.bold : FontWeight.normal,
                    fontStyle: isGuessCheck ? FontStyle.normal : FontStyle.italic,
                    color: isGuessCheck ? Colors.orange.shade900 : theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
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
      child: Row(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      '${message.sentAt.hour.toString().padLeft(2, '0')}:${message.sentAt.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isMe
                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 40),
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
