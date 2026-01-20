import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/message.dart';
import '../bloc/chat_bloc.dart';
import 'media_message_content.dart';

/// Message bubble widget for chat.
class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool showTail;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showTail = true,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: isMe ? 48 : 12,
            right: isMe ? 12 : 48,
            top: showTail ? 8 : 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Message content
              IntrinsicWidth(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                padding: message.isMediaMessage
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 8,
                        bottom: 8,
                      ),
                decoration: BoxDecoration(
                  color: isMe
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe && showTail ? 18 : 4),
                    bottomRight: Radius.circular(!isMe && showTail ? 18 : 4),
                  ),
                ),
                child: message.isDeleted
                    ? _DeletedMessage(isMe: isMe, theme: theme)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Media content
                          if (message.isMediaMessage)
                            MediaMessageContent(
                              message: message,
                              isSent: isMe,
                            ),

                          // Caption or text
                          if (message.text.isNotEmpty &&
                              message.type != MessageType.text)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 10,
                                right: 10,
                                top: 4,
                                bottom: 6,
                              ),
                              child: _MessageText(
                                message: message,
                                isMe: isMe,
                                theme: theme,
                              ),
                            ),

                          // Text-only message with inline time (WhatsApp style)
                          if (!message.isMediaMessage &&
                              message.text.isNotEmpty)
                            _MessageTextWithTime(
                              message: message,
                              isMe: isMe,
                              theme: theme,
                            ),

                          // For media messages, show time separately below
                          if (message.isMediaMessage)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: _MessageMeta(
                                  message: message,
                                  isMe: isMe,
                                  theme: theme,
                                ),
                              ),
                            ),
                        ],
                      ),
                ),
              ),
              // Retry button for failed messages
              if (isMe && message.status == MessageStatus.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: InkWell(
                    onTap: () {
                      context.read<ChatBloc>().add(ChatRetryMessage(message));
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to retry',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeData theme;

  const _MessageText({
    required this.message,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      message.text,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        height: 1.3,
      ),
    );
  }
}

/// Text message with inline time at bottom-right (WhatsApp style)
class _MessageTextWithTime extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeData theme;

  const _MessageTextWithTime({
    required this.message,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(
          message.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            height: 1.3,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: _MessageMeta(
            message: message,
            isMe: isMe,
            theme: theme,
          ),
        ),
      ],
    );
  }
}

class _DeletedMessage extends StatelessWidget {
  final bool isMe;
  final ThemeData theme;

  const _DeletedMessage({
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.block,
          size: 14,
          color: isMe
              ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          'Message deleted',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isMe
                ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                : theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final Message message;
  final bool isMe;
  final ThemeData theme;

  const _MessageMeta({
    required this.message,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(message.sentAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: isMe
                ? theme.colorScheme.onPrimary.withValues(alpha: 0.5)
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _StatusIcon(status: message.status, theme: theme, isMe: isMe),
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

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final ThemeData theme;
  final bool isMe;

  const _StatusIcon({
    required this.status,
    required this.theme,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
        : theme.colorScheme.onSurfaceVariant;

    return switch (status) {
      // Don't show any icon for sending - let it be invisible during upload
      MessageStatus.sending => const SizedBox.shrink(),
      
      // Single gray check mark for sent (message reached server)
      MessageStatus.sent => Icon(
          Icons.check,
          size: 16,
          color: iconColor,
        ),
      
      // Double gray check marks for delivered (message delivered to recipient's device)
      MessageStatus.delivered => Icon(
          Icons.done_all,
          size: 16,
          color: iconColor,
        ),
      
      // Double blue check marks for read (message opened/read by recipient)
      MessageStatus.read => const Icon(
          Icons.done_all,
          size: 16,
          color: Colors.blue,
        ),
      
      // Error icon for failed
      MessageStatus.failed => Icon(
          Icons.error_outline,
          size: 16,
          color: theme.colorScheme.error,
        ),
    };
  }
}

/// Typing indicator widget.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final delay = index * 0.2;
                final value = (_controller.value + delay) % 1.0;
                final bounce = (value < 0.5) ? value * 2 : 2 - (value * 2);

                return Container(
                  margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
                  child: Transform.translate(
                    offset: Offset(0, -4 * bounce),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// Date separator for chat messages.
class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDate(date),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else if (now.difference(date).inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
