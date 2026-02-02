import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/random_group_message.dart';
import '../bloc/random_group_bloc.dart';
import '../bloc/random_group_chat_bloc.dart';

/// Chat page for random groups.
///
/// Features:
/// - Real-time messaging
/// - Only approved members can view and send messages
/// - Message pagination
class RandomGroupChatPage extends StatefulWidget {
  final String groupId;

  const RandomGroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  State<RandomGroupChatPage> createState() => _RandomGroupChatPageState();
}

class _RandomGroupChatPageState extends State<RandomGroupChatPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoadingMore = false;
  RandomGroupChatBloc? _chatBloc;

  @override
  void initState() {
    super.initState();
    // CRITICAL: Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadGroupDetails();
    _openChat();
  }

  void _loadGroupDetails() {
    context.read<RandomGroupBloc>().add(LoadRandomGroupDetails(widget.groupId));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC reference for safe disposal
    _chatBloc ??= context.read<RandomGroupChatBloc>();
  }

  /// CRITICAL: Handle app lifecycle changes for reliable message delivery.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - resync to get any missed messages
        _chatBloc?.add(const ResyncRandomGroupChat());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App going to background - subscriptions may become stale
        // We'll resync when resumed
        break;
    }
  }

  void _openChat() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      // Notify notification service that user is viewing this group
      try {
        getIt<NotificationService>().setCurrentGroup(widget.groupId);
      } catch (_) {
        // Ignore if service not available
      }

      context.read<RandomGroupChatBloc>().add(OpenRandomGroupChat(
            groupId: widget.groupId,
            userId: authState.user.id,
            username: authState.user.username,
            userName: authState.user.displayName,
            userPhotoUrl: authState.user.avatarUrl,
          ));
    }
  }

  @override
  void dispose() {
    // CRITICAL: Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();

    // Notify notification service that user left this group
    try {
      getIt<NotificationService>().clearCurrentGroup();
    } catch (_) {
      // Ignore if service not available
    }

    // Use cached reference to avoid context access after disposal
    _chatBloc?.add(const CloseRandomGroupChat());
    super.dispose();
  }

  void _onScroll() {
    // Load more when near top (inverted list)
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      final state = context.read<RandomGroupChatBloc>().state;
      if (state.hasMore && state.status != RandomGroupChatStatus.loading) {
        _isLoadingMore = true;
        context
            .read<RandomGroupChatBloc>()
            .add(const LoadMoreRandomGroupMessages());
      }
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<RandomGroupChatBloc>().add(SendRandomGroupMessage(text));
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

    return BlocBuilder<RandomGroupBloc, RandomGroupState>(
      builder: (context, groupState) {
        final group = groupState.selectedGroup;
        final groupName = group?.name ?? 'Group Chat';

        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () => context.push(
                Routes.randomGroupDetailWith(widget.groupId),
              ),
              borderRadius: BorderRadius.circular(24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      groupName.isNotEmpty ? groupName[0].toUpperCase() : '?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupName,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (group != null)
                          Text(
                            '${group.memberCount} members',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => context.push(
                  Routes.randomGroupDetailWith(widget.groupId),
                ),
                icon: const Icon(Icons.info_outline),
                tooltip: 'Group Info',
              ),
            ],
          ),
          body: BlocConsumer<RandomGroupChatBloc, RandomGroupChatState>(
            listener: (context, state) {
              // Reset loading more flag
              if (state.status != RandomGroupChatStatus.loading) {
                _isLoadingMore = false;
              }

              // Handle access denial - navigate away with error
              if (state.status == RandomGroupChatStatus.error && 
                  !state.membershipVerified) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage ?? 'Access denied'),
                    backgroundColor: theme.colorScheme.error,
                    duration: const Duration(seconds: 3),
                  ),
                );
                // Navigate back - user should not be on this page
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(Routes.randomGroups);
                }
                return;
              }

              // Show other errors
              if (state.status == RandomGroupChatStatus.error && 
                  state.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage!),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              }
            },
            builder: (context, state) {
              // ================================================================
              // SECURITY: Show loading while verifying membership
              // Do NOT show any content until membership is confirmed
              // ================================================================
              if (state.isVerifyingMembership) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Verifying access...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // SECURITY: Show access denied state for non-members
              if (state.status == RandomGroupChatStatus.error && 
                  !state.membershipVerified) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Access Denied',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage ?? 'You must be an approved member to access this chat.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(Routes.randomGroups);
                          }
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
                  ),
                );
              }

              // Only show loading spinner during initial load
              if (state.status == RandomGroupChatStatus.loading && 
                  state.messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              // Determine if we're truly empty or still loading
              final isLoading = state.status == RandomGroupChatStatus.loading;

              return Column(
                children: [
                  // Messages list
                  Expanded(
                    child: state.messages.isEmpty
                        ? (isLoading
                            ? const SizedBox.shrink() // Don't show empty state while loading
                            : _buildEmptyState(theme))
                        : _buildMessagesList(state),
                  ),

                  // Input area (only show if membership verified)
                  if (state.membershipVerified) _buildInputArea(theme, state),
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

  Widget _buildMessagesList(RandomGroupChatState state) {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: state.messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final message = state.messages[index];
        final isMe = message.senderId == state.currentUserId;

        return _MessageBubble(
          message: message,
          isMe: isMe,
        );
      },
    );
  }

  Widget _buildInputArea(ThemeData theme, RandomGroupChatState state) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final RandomGroupMessage message;
  final bool isMe;

  const _MessageBubble({
    required this.message,
    required this.isMe,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CachedAvatar(
              imageUrl: message.senderPhotoUrl,
              name: message.senderName ?? message.senderUsername ?? '?',
              radius: 16,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? theme.colorScheme.primary
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
                  if (!isMe) ...[
                    Text(
                      message.senderName ??
                          message.senderUsername ??
                          'Unknown',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isMe
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(message.sentAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isMe
                          ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24 && time.day == now.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
}
