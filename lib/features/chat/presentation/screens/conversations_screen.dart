import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/domain/entities/connection.dart';
import '../../data/chat_cache_service.dart';
import '../../data/chat_service.dart';
import '../../domain/entities/conversation.dart';
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

  void _showSearch() {
    showSearch(
      context: context,
      delegate: _ConversationSearchDelegate(
        currentUserId: widget.currentUserId,
        onConversationTap: widget.onConversationTap,
      ),
    );
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
            onPressed: _showSearch,
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
                  // Cap animation delay at 10 items to prevent unbounded growth
                  duration: Duration(milliseconds: 300 + (index.clamp(0, 10) * 50)),
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
                      // Preload chat messages into cache on long-press.
                      // Uses ChatCacheService + ChatService directly (both singletons).
                      final cacheService = getIt<ChatCacheService>();
                      if (cacheService.hasValidCache(conversation.id)) return;
                      getIt<ChatService>()
                          .getMessagesOnce(conversation.id)
                          .then((msgs) {
                        if (msgs.isNotEmpty) {
                          cacheService.updateCache(
                            conversationId: conversation.id,
                            messages: msgs,
                            hasMore: msgs.length >= 50,
                            isPreload: true,
                          );
                        }
                      }).catchError((_) {});
                    },
                    onConfirmDismiss: (direction) async {
                      // Require confirmation for destructive actions
                      final action = direction == DismissDirection.endToStart
                          ? 'Delete'
                          : 'Archive';
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('$action conversation?'),
                          content: Text(
                            direction == DismissDirection.endToStart
                                ? 'This will permanently delete this conversation.'
                                : 'This conversation will be archived.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: direction == DismissDirection.endToStart
                                  ? TextButton.styleFrom(
                                      foregroundColor:
                                          Theme.of(context).colorScheme.error)
                                  : null,
                              child: Text(action),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        if (direction == DismissDirection.endToStart) {
                          if (context.mounted) {
                            context.read<ConversationsBloc>().add(
                                  ConversationsDelete(
                                      conversationId: conversation.id),
                                );
                          }
                        } else {
                          if (context.mounted) {
                            context.read<ConversationsBloc>().add(
                                  ConversationsArchive(
                                      conversationId: conversation.id),
                                );
                          }
                        }
                      }
                      return confirmed ?? false;
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
  final Future<bool> Function(DismissDirection) onConfirmDismiss;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.onTap,
    this.onPreload,
    required this.onConfirmDismiss,
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
      confirmDismiss: widget.onConfirmDismiss,
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
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
                    Icons.check,
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
                  color: widget.conversation.getUnreadCount(widget.currentUserId) > 0
                      ? const Color(0xFF25D366) // green when unread
                      : theme.colorScheme.outline,
                  fontWeight: widget.conversation.getUnreadCount(widget.currentUserId) > 0
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              if (widget.conversation.getUnreadCount(widget.currentUserId) > 0) ...[
                const SizedBox(height: 4),
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
                    widget.conversation.getUnreadCount(widget.currentUserId) > 99
                        ? '99+'
                        : widget.conversation.getUnreadCount(widget.currentUserId).toString(),
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

/// Search delegate for filtering conversations.
class _ConversationSearchDelegate extends SearchDelegate<Conversation?> {
  final String currentUserId;
  final void Function(Conversation conversation) onConversationTap;

  _ConversationSearchDelegate({
    required this.currentUserId,
    required this.onConversationTap,
  }) : super(
          searchFieldLabel: 'Search conversations...',
          searchFieldStyle: const TextStyle(fontSize: 16),
        );

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    return BlocBuilder<ConversationsBloc, ConversationsState>(
      builder: (context, state) {
        if (state.status == ConversationsStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.conversations.isEmpty) {
          return const Center(
            child: Text('No conversations yet'),
          );
        }

        // Filter conversations based on search query
        final filteredConversations = query.isEmpty
            ? state.conversations
            : state.conversations.where((conversation) {
                final otherParticipant =
                    conversation.getOtherParticipantInfo(currentUserId);
                final participantName =
                    (otherParticipant?.displayName ?? '').toLowerCase();
                final lastMessage =
                    (conversation.lastMessageText ?? '').toLowerCase();
                final searchLower = query.toLowerCase();

                return participantName.contains(searchLower) ||
                    lastMessage.contains(searchLower);
              }).toList();

        if (filteredConversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No conversations found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: filteredConversations.length,
          itemBuilder: (context, index) {
            final conversation = filteredConversations[index];
            final otherParticipant =
                conversation.getOtherParticipantInfo(currentUserId);

            return ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: otherParticipant?.photoUrl != null
                    ? NetworkImage(otherParticipant!.photoUrl!)
                    : null,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: otherParticipant?.photoUrl == null
                    ? Text(
                        (otherParticipant?.displayName ?? '?')[0].toUpperCase(),
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              title: Text(
                otherParticipant?.displayName ?? 'Unknown',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                conversation.lastMessageText ?? 'No messages yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              trailing: conversation.getUnreadCount(currentUserId) > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        conversation.getUnreadCount(currentUserId) > 99
                            ? '99+'
                            : conversation
                                .getUnreadCount(currentUserId)
                                .toString(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                close(context, conversation);
                onConversationTap(conversation);
              },
            );
          },
        );
      },
    );
  }
}
