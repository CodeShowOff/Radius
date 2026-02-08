import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/pending_requests_sheet.dart';
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

    // CRITICAL FIX: Set group context IMMEDIATELY to prevent race condition
    // This must be the FIRST operation to ensure no notifications slip through
    // while the screen is initializing
    try {
      getIt<NotificationService>().setCurrentGroup(widget.groupId);
    } catch (_) {
      // Ignore if service not available
    }

    // CRITICAL: Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _loadGroupDetails();
    _openChat();
  }

  void _loadGroupDetails() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final bloc = context.read<RandomGroupBloc>();
      bloc.add(LoadRandomGroupDetails(widget.groupId));
      // Check membership status to determine if user is admin
      bloc.add(CheckMembershipStatus(
        groupId: widget.groupId,
        userId: authState.user.id,
      ));
    }
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

  void _confirmClearChat() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // Capture the blocs before showing dialog to ensure they're accessible
    final randomGroupBloc = context.read<RandomGroupBloc>();
    final chatBloc = context.read<RandomGroupChatBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Are you sure you want to clear all messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);

              // Clear messages from UI immediately for instant feedback
              chatBloc.add(const ClearRandomGroupChatMessages());

              // Clear messages from backend (will also trigger stream update)
              randomGroupBloc.add(ClearRandomGroupChat(
                groupId: widget.groupId,
                adminUserId: authState.user.id,
              ));

              // Show confirmation message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chat cleared'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showPendingRequestsSheet(
      BuildContext context, RandomGroupState groupState) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final bloc = context.read<RandomGroupBloc>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (modalContext) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<RandomGroupBloc, RandomGroupState>(
          builder: (builderContext, state) {
            final updatedRequests = state.pendingRequests
                .map((r) => PendingRequestItem(
                      id: r.id,
                      userId: r.requesterId,
                      displayName:
                          r.requesterDisplayName ?? r.requesterUsername,
                      username: r.requesterUsername,
                      photoUrl: r.requesterPhotoUrl,
                      message: r.message,
                      requestedAt: r.requestedAt,
                    ))
                .toList();

            return PendingRequestsSheet(
              requests: updatedRequests,
              onApprove: (request) {
                builderContext.read<RandomGroupBloc>().add(ApproveJoinRequest(
                      groupId: widget.groupId,
                      requestId: request.id,
                      adminId: authState.user.id,
                      requesterUsername: request.displayName,
                    ));
              },
              onReject: (request) {
                builderContext.read<RandomGroupBloc>().add(RejectJoinRequest(
                      groupId: widget.groupId,
                      requestId: request.id,
                      adminId: authState.user.id,
                    ));
              },
              onAcceptAll: () {
                builderContext
                    .read<RandomGroupBloc>()
                    .add(ApproveAllJoinRequests(
                      groupId: widget.groupId,
                      adminId: authState.user.id,
                    ));
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<RandomGroupBloc, RandomGroupState>(
      builder: (context, groupState) {
        final group = groupState.selectedGroup;
        final groupName = group?.name ?? 'Group Chat';
        final isAdmin =
            groupState.membershipStatus == UserMembershipStatus.admin ||
                groupState.membershipStatus == UserMembershipStatus.creator;
        final hasPendingRequests = groupState.pendingRequests.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () {
                if (isAdmin && hasPendingRequests) {
                  _showPendingRequestsSheet(context, groupState);
                } else {
                  context.push(
                    Routes.randomGroupDetailWith(widget.groupId),
                  );
                }
              },
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
              // Show dot badge for pending requests (admin only)
              if (isAdmin && hasPendingRequests)
                IconButton(
                  onPressed: () =>
                      _showPendingRequestsSheet(context, groupState),
                  icon: Badge(
                    backgroundColor: theme.colorScheme.error,
                    smallSize: 10,
                    child: const Icon(Icons.person_add),
                  ),
                  tooltip: 'Pending join requests',
                ),
              IconButton(
                onPressed: () => context.push(
                  Routes.randomGroupDetailWith(widget.groupId),
                ),
                icon: const Icon(Icons.info_outline),
                tooltip: 'Group Info',
              ),
              // Clear chat option for admins
              if (isAdmin)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'clear') {
                      _confirmClearChat();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear chat'),
                    ),
                  ],
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
                        state.errorMessage ??
                            'You must be an approved member to access this chat.',
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
                            ? const SizedBox
                                .shrink() // Don't show empty state while loading
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      itemCount: state.messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
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
        );
      },
    );
  }

  bool _shouldShowSenderInfo(RandomGroupChatState state, int index) {
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

  Widget _buildInputArea(ThemeData theme, RandomGroupChatState state) {
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
              onPressed: state.status == RandomGroupChatStatus.sending
                  ? null
                  : _sendMessage,
              icon: state.status == RandomGroupChatStatus.sending
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

class _MessageBubble extends StatelessWidget {
  final RandomGroupMessage message;
  final bool isMe;
  final bool showSenderInfo;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showSenderInfo,
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
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar for other users
          if (!isMe) ...[
            if (showSenderInfo)
              CachedAvatar(
                imageUrl: message.senderPhotoUrl,
                name: message.senderName ?? message.senderUsername ?? '?',
                radius: 16,
              )
            else
              const SizedBox(width: 32), // Placeholder for alignment
            const SizedBox(width: 8),
          ],

          // Message content
          IntrinsicWidth(
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sender name for other users
                  if (!isMe &&
                      showSenderInfo &&
                      (message.senderName != null ||
                          message.senderUsername != null))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName ??
                            message.senderUsername ??
                            'Unknown',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  // Message text with inline time (WhatsApp style)
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Text(
                        message.text,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: isMe
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.sentAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isMe
                                    ? theme.colorScheme.onPrimaryContainer
                                        .withValues(alpha: 0.5)
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

    if (diff.inDays > 0) {
      return '${time.day}/${time.month} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
