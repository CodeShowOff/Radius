import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/domain/entities/connection.dart';
import '../../domain/entities/conversation.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/conversations_bloc.dart';

/// Screen showing the list of conversations for a user.
class ConversationsScreen extends StatefulWidget {
  final String currentUserId;
  final void Function(Conversation conversation) onConversationTap;

  const ConversationsScreen({
    super.key,
    required this.currentUserId,
    required this.onConversationTap,
  });

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  @override
  void initState() {
    super.initState();
    // Only load if not already loaded for this user
    // The BLoC will handle checking if data is already available
    // and will skip redundant loads while keeping real-time streams active
    final state = context.read<ConversationsBloc>().state;
    if (state.status == ConversationsStatus.initial ||
        state.currentUserId != widget.currentUserId) {
      context.read<ConversationsBloc>().add(
            ConversationsLoad(userId: widget.currentUserId),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
        ],
      ),
      body: BlocBuilder<ConversationsBloc, ConversationsState>(
        builder: (context, state) {
          // Only show loading on initial load with no cached data
          if (state.status == ConversationsStatus.loading &&
              state.conversations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          // Show error only if we have no cached data to display
          if (state.status == ConversationsStatus.error &&
              state.conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(state.errorMessage ?? 'Failed to load conversations'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<ConversationsBloc>().add(
                            ConversationsLoad(userId: widget.currentUserId),
                          );
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state.conversations.isEmpty) {
            return _EmptyState(theme: theme);
          }

          return RefreshIndicator(
            onRefresh: () async {
              context.read<ConversationsBloc>().add(
                    const ConversationsRefresh(),
                  );
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              itemCount: state.conversations.length,
              itemBuilder: (context, index) {
                final conversation = state.conversations[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + (index * 50)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(
                        opacity: value,
                        child: child,
                      ),
                    );
                  },
                  child: _ConversationTile(
                    conversation: conversation,
                    currentUserId: widget.currentUserId,
                    onTap: () => widget.onConversationTap(conversation),
                    onPreload: () {
                      // Preload chat messages into cache on long-press
                      // This makes navigation instant even on cache miss
                      getIt<ChatBloc>().add(
                        ChatPreload(conversationId: conversation.id),
                      );
                    },
                    onDismissed: (direction) {
                      if (direction == DismissDirection.endToStart) {
                        // Delete
                        context.read<ConversationsBloc>().add(
                              ConversationsDelete(
                                  conversationId: conversation.id),
                            );
                      } else {
                        // Archive
                        context.read<ConversationsBloc>().add(
                              ConversationsArchive(
                                  conversationId: conversation.id),
                            );
                      }
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ThemeData theme;

  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'No conversations yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a chat with people nearby to begin messaging',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  final Conversation conversation;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback? onPreload;
  final void Function(DismissDirection) onDismissed;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
    this.onPreload,
    required this.onDismissed,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  Connection? _connection;

  @override
  void initState() {
    super.initState();
    _checkConnectionStatus();
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final otherUserId =
          widget.conversation.getOtherParticipantId(widget.currentUserId);
      final connectionService = getIt<ConnectionService>();
      final connection = await connectionService.getConnection(
        widget.currentUserId,
        otherUserId,
      );
      if (mounted) {
        setState(() {
          _connection = connection;
        });
      }
    } catch (e) {
      // Connection check failed, continue without connection info
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherParticipant =
        widget.conversation.getOtherParticipantInfo(widget.currentUserId);
    final isMuted = widget.conversation.isMutedBy(widget.currentUserId);
    final isDisconnected = _connection?.status == ConnectionStatus.disconnected;
    final isBlocked = _connection?.status == ConnectionStatus.blocked;

    return Dismissible(
      key: Key(widget.conversation.id),
      background: Container(
        color: theme.colorScheme.secondary,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.onSecondary,
        ),
      ),
      secondaryBackground: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onError,
        ),
      ),
      onDismissed: widget.onDismissed,
      child: GestureDetector(
        onLongPressStart: (_) => widget.onPreload?.call(),
        child: Container(
          color: isDisconnected || isBlocked
              ? theme.colorScheme.errorContainer.withValues(alpha: 0.1)
              : null,
          child: ListTile(
            leading: CircleAvatar(
              radius: 28,
              backgroundImage: otherParticipant?.photoUrl != null
                  ? NetworkImage(otherParticipant!.photoUrl!)
                : null,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: otherParticipant?.photoUrl == null
                ? Text(
                    (otherParticipant?.displayName ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  otherParticipant?.displayName ?? 'Unknown',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isDisconnected)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Disconnected',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              if (isBlocked)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block,
                        size: 10,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Blocked',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              if (isMuted && !isDisconnected && !isBlocked)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.notifications_off,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              if (widget.conversation.lastMessageSenderId ==
                  widget.currentUserId)
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
                  widget.conversation.lastMessageText ?? 'No messages yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widget.conversation.getUnreadCount(widget.currentUserId) > 0
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.outline,
                    fontWeight: widget.conversation.getUnreadCount(widget.currentUserId) > 0
                        ? FontWeight.w600
                        : FontWeight.normal,
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
              Text(
                _formatTime(widget.conversation.lastMessageAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (widget.conversation.getUnreadCount(widget.currentUserId) > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.conversation.getUnreadCount(widget.currentUserId) > 99
                        ? '99+'
                        : widget.conversation.getUnreadCount(widget.currentUserId).toString(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: widget.onTap,
        ),
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';

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
      return '${time.day}/${time.month}';
    }
  }
}
