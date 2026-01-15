import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/message.dart';
import '../bloc/chat_bloc.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Open the chat
    context.read<ChatBloc>().add(ChatOpen(
          conversationId: widget.conversationId,
          currentUserId: widget.currentUserId,
          otherUserId: widget.otherUserId,
          otherUserName: widget.otherUserName,
          otherUserPhotoUrl: widget.otherUserPhotoUrl,
        ));
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    context.read<ChatBloc>().add(const ChatClose());
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
    return Scaffold(
      appBar: _ChatAppBar(
        name: widget.otherUserName,
        photoUrl: widget.otherUserPhotoUrl,
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
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
          ChatInput(
            onSend: _sendMessage,
            onTypingChanged: _onTypingChanged,
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

  const _ChatAppBar({
    required this.name,
    this.photoUrl,
    required this.onBackPressed,
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
          onSelected: (value) {
            // Handle menu actions
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'mute',
              child: Text('Mute notifications'),
            ),
            const PopupMenuItem(
              value: 'clear',
              child: Text('Clear chat'),
            ),
            const PopupMenuItem(
              value: 'block',
              child: Text('Block user'),
            ),
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
