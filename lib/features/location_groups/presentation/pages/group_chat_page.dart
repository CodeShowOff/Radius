import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/group_message.dart';
import '../bloc/group_chat_bloc.dart';
import '../bloc/location_group_bloc.dart';

/// Page for group chat with real-time messaging.
class GroupChatPage extends StatefulWidget {
  final String groupId;

  const GroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoadingMore = false;
  late final GroupChatBloc _chatBloc;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _openChat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC reference for safe disposal
    _chatBloc = context.read<GroupChatBloc>();
  }

  void _openChat() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<GroupChatBloc>().add(OpenGroupChat(
            groupId: widget.groupId,
            currentUserId: authState.user.id,
            currentUserName: authState.user.displayName,
            currentUserPhotoUrl: authState.user.avatarUrl,
          ));
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    // Use cached reference to avoid context access after disposal
    _chatBloc.add(const CloseGroupChat());
    super.dispose();
  }

  void _onScroll() {
    // Load more when near top (inverted list)
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      final state = context.read<GroupChatBloc>().state;
      if (state.hasMore && !state.isLoading) {
        _isLoadingMore = true;
        context.read<GroupChatBloc>().add(const LoadMoreGroupMessages());
      }
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<GroupChatBloc>().add(SendGroupMessage(text));
    _messageController.clear();

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<LocationGroupBloc, LocationGroupState>(
      builder: (context, groupState) {
        final group = groupState.currentGroup;
        final groupName = group?.name ?? 'Group Chat';

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(groupName),
                if (group != null)
                  Text(
                    '${group.memberCount} members',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.info_outline),
                tooltip: 'Group Info',
              ),
            ],
          ),
          body: BlocConsumer<GroupChatBloc, GroupChatState>(
            listener: (context, state) {
              // Reset loading more flag
              if (!state.isLoading) {
                _isLoadingMore = false;
              }

              // Show error
              if (state.hasError && state.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage!),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              }
            },
            builder: (context, state) {
              if (state.isLoading && state.messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              return Column(
                children: [
                  // Messages list
                  Expanded(
                    child: state.messages.isEmpty
                        ? _buildEmptyState(theme)
                        : _buildMessagesList(state),
                  ),

                  // Input area
                  _buildInputArea(theme, state),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(GroupChatState state) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      itemCount: state.messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the end (top when reversed)
        if (index == state.messages.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final message = state.messages[index];
        final isMe = message.senderId == state.currentUserId;
        final showSenderInfo = !isMe && _shouldShowSenderInfo(state, index);

        return _MessageBubble(
          message: message,
          isMe: isMe,
          showSenderInfo: showSenderInfo,
          onDelete: isMe
              ? () => _confirmDelete(message)
              : null,
        );
      },
    );
  }

  bool _shouldShowSenderInfo(GroupChatState state, int index) {
    // Always show for first message (at the bottom visually)
    if (index == state.messages.length - 1) return true;

    final message = state.messages[index];
    final nextMessage = state.messages[index + 1];

    // Show if sender changed
    if (message.senderId != nextMessage.senderId) return true;

    // Show if there's a time gap of more than 5 minutes
    final timeDiff = message.sentAt.difference(nextMessage.sentAt);
    if (timeDiff.inMinutes > 5) return true;

    return false;
  }

  void _confirmDelete(GroupMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<GroupChatBloc>().add(DeleteGroupMessage(message.id));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, GroupChatState state) {
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: state.isSending ? null : _sendMessage,
              icon: state.isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual message bubble widget.
class _MessageBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMe;
  final bool showSenderInfo;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showSenderInfo,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // System messages
    if (message.isSystemMessage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar for other users
          if (!isMe) ...[
            if (showSenderInfo)
              CircleAvatar(
                radius: 16,
                backgroundImage: message.senderPhotoUrl != null
                    ? NetworkImage(message.senderPhotoUrl!)
                    : null,
                child: message.senderPhotoUrl == null
                    ? Text(
                        (message.senderName ?? '?')[0].toUpperCase(),
                        style: theme.textTheme.bodySmall,
                      )
                    : null,
              )
            else
              const SizedBox(width: 32), // Placeholder for alignment
            const SizedBox(width: 8),
          ],

          // Message content
          Flexible(
            child: GestureDetector(
              onLongPress: onDelete,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isMe
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender name for other users
                    if (!isMe && showSenderInfo && message.senderName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          message.senderName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                    // Message text
                    Text(
                      message.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isMe
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),

                    // Timestamp
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(message.sentAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isMe
                            ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                            : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) {
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
