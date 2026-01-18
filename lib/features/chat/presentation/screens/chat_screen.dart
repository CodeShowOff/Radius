import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/domain/entities/connection.dart';
import '../../domain/entities/message.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/conversations_bloc.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

/// Main chat screen for a conversation.
class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  Connection? _connection;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _checkConnectionStatus();

    // Open the chat
    context.read<ChatBloc>().add(ChatOpen(
          conversationId: widget.conversationId,
          currentUserId: widget.currentUserId,
          otherUserId: widget.otherUserId,
          otherUserName: widget.otherUserName,
          otherUserPhotoUrl: widget.otherUserPhotoUrl,
        ));
  }

  Future<void> _checkConnectionStatus() async {
    try {
      final connectionService = getIt<ConnectionService>();
      final connection = await connectionService.getConnection(
        widget.currentUserId,
        widget.otherUserId,
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

  late final ChatBloc _chatBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC reference for safe disposal
    _chatBloc = context.read<ChatBloc>();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // Use cached reference to avoid context access after disposal
    _chatBloc.add(const ChatClose());
    super.dispose();
  }

  void _onScroll() {
    // Load more when near top (inverted list)
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      final bloc = context.read<ChatBloc>();
      if (bloc.state.hasMore && bloc.state.status != ChatStatus.loading) {
        _isLoadingMore = true;
        bloc.add(const ChatLoadMore());
      }
    }
  }

  void _sendMessage(String text) {
    context.read<ChatBloc>().add(ChatSendMessage(text));

    // Scroll to bottom after sending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTypingChanged(bool isTyping) {
    context.read<ChatBloc>().add(ChatSetTyping(isTyping));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDisconnected =
        _connection?.status == ConnectionStatus.disconnected;
    final bool isBlocked = _connection?.status == ConnectionStatus.blocked;

    return Scaffold(
      appBar: _ChatAppBar(
        name: widget.otherUserName,
        photoUrl: widget.otherUserPhotoUrl,
        onBackPressed: () => Navigator.of(context).pop(),
        onMenuSelected: (value) => _handleMenuAction(context, value),
        isDisconnected: isDisconnected,
        isBlocked: isBlocked,
      ),
      body: Column(
        children: [
          // Disconnection banner
          if (isDisconnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.link_off,
                    size: 20,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connection removed. You can view old messages but cannot send new ones.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (isBlocked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.block,
                    size: 20,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This user has been blocked. You can view old messages.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Messages list
          Expanded(
            child: BlocConsumer<ChatBloc, ChatState>(
              listenWhen: (previous, current) =>
                  previous.status != current.status,
              listener: (context, state) {
                if (state.status != ChatStatus.loading) {
                  _isLoadingMore = false;
                }
              },
              builder: (context, state) {
                if (state.status == ChatStatus.loading &&
                    state.messages.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (state.status == ChatStatus.error) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 16),
                        Text(state.errorMessage ?? 'Failed to load messages'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            context.read<ChatBloc>().add(ChatOpen(
                                  conversationId: widget.conversationId,
                                  currentUserId: widget.currentUserId,
                                  otherUserId: widget.otherUserId,
                                  otherUserName: widget.otherUserName,
                                  otherUserPhotoUrl: widget.otherUserPhotoUrl,
                                ));
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                return _MessagesList(
                  messages: state.allMessages,
                  currentUserId: state.currentUserId ?? widget.currentUserId,
                  isTyping: state.isOtherUserTyping,
                  hasMore: state.hasMore,
                  scrollController: _scrollController,
                );
              },
            ),
          ),

          // Input
          if (!isDisconnected && !isBlocked)
            ChatInput(
              onSend: _sendMessage,
              onTypingChanged: _onTypingChanged,
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Text(
                isBlocked
                    ? 'You cannot send messages to a blocked user'
                    : 'You cannot send messages. Connection has been removed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'delete':
        _confirmDeleteConversation(context);
        break;
      case 'mute':
        // TODO: Implement mute
        break;
      case 'clear':
        // TODO: Implement clear
        break;
      case 'block':
        // TODO: Navigate to connection management
        break;
    }
  }

  void _confirmDeleteConversation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Conversation?'),
        content: const Text(
          'This will permanently delete all messages in this conversation. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Delete conversation via conversations bloc
              context.read<ConversationsBloc>().add(
                    ConversationsDelete(conversationId: widget.conversationId),
                  );

              // Go back to conversations list
              Navigator.of(context).pop();

              // Show confirmation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Conversation deleted'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String name;
  final String? photoUrl;
  final VoidCallback onBackPressed;
  final void Function(String) onMenuSelected;
  final bool isDisconnected;
  final bool isBlocked;

  const _ChatAppBar({
    required this.name,
    this.photoUrl,
    required this.onBackPressed,
    required this.onMenuSelected,
    this.isDisconnected = false,
    this.isBlocked = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed,
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: photoUrl == null
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Could show online status here
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: onMenuSelected,
          itemBuilder: (context) => [
            if (isDisconnected || isBlocked)
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text(
                    'Delete Conversation',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              )
            else ...const [
              PopupMenuItem(
                value: 'mute',
                child: Text('Mute notifications'),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete conversation'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MessagesList extends StatelessWidget {
  final List<Message> messages;
  final String currentUserId;
  final bool isTyping;
  final bool hasMore;
  final ScrollController scrollController;

  const _MessagesList({
    required this.messages,
    required this.currentUserId,
    required this.isTyping,
    required this.hasMore,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !isTyping) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Say hello! 👋',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      reverse: true, // Most recent at bottom
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length + (hasMore ? 1 : 0) + (isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        // Typing indicator at index 0 (bottom of reversed list)
        if (isTyping && index == 0) {
          return const TypingIndicator();
        }

        // Adjust index for typing indicator
        final adjustedIndex = isTyping ? index - 1 : index;

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
            if (showDate) DateSeparator(date: message.sentAt),
            MessageBubble(
              message: message,
              isMe: isMe,
              showTail: showTail,
            ),
          ],
        );
      },
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
