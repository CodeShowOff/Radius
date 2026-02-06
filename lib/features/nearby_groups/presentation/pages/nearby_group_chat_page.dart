import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/nearby_group_message.dart';
import '../bloc/nearby_group_bloc.dart';
import '../bloc/nearby_group_chat_bloc.dart';

/// Chat page for nearby groups.
///
/// Features:
/// - Real-time messaging with optimistic updates
/// - Member presence indicator
/// - Auto-joined via Bluetooth (no explicit join)
/// - SECURITY: Membership verification before showing content
/// - Lifecycle handling for app resume resync
class NearbyGroupChatPage extends StatefulWidget {
  final String groupId;

  const NearbyGroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  State<NearbyGroupChatPage> createState() => _NearbyGroupChatPageState();
}

class _NearbyGroupChatPageState extends State<NearbyGroupChatPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoadingMore = false;
  NearbyGroupChatBloc? _chatBloc;

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
    _resumeScanning();
  }

  void _loadGroupDetails() {
    context.read<NearbyGroupBloc>().add(LoadNearbyGroupDetails(widget.groupId));
  }

  void _resumeScanning() {
    // Resume scanning when entering chat (if user is the creator)
    final groupBloc = context.read<NearbyGroupBloc>();
    final groupState = groupBloc.state;
    final authState = context.read<AuthBloc>().state;
    
    if (authState is AuthAuthenticated && 
        groupState.myActiveGroup != null &&
        groupState.myActiveGroup!.id == widget.groupId &&
        groupState.myActiveGroup!.creatorId == authState.user.id) {
      // User is viewing their own group - ensure scanning is active
      if (!groupState.isScanning) {
        groupBloc.add(StartGroupScanning(
          groupId: widget.groupId,
          creatorId: authState.user.id,
          creatorUsername: authState.user.username,
        ));
      }
    }
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC reference for safe disposal
    _chatBloc ??= context.read<NearbyGroupChatBloc>();
  }

  /// CRITICAL: Handle app lifecycle changes for reliable message delivery.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - resync to get any missed messages
        _chatBloc?.add(const ResyncNearbyGroupChat());
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
      context.read<NearbyGroupChatBloc>().add(OpenNearbyGroupChat(
            groupId: widget.groupId,
            currentUserId: authState.user.id,
            currentUsername: authState.user.username,
            currentUserName: authState.user.displayName,
            currentUserPhotoUrl: authState.user.avatarUrl,
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

    // Note: We DON'T stop scanning here because the group should stay alive
    // Scanning continues in the background even when user navigates away
    // Use cached reference to close chat subscription only
    _chatBloc?.add(const CloseNearbyGroupChat());
    super.dispose();
  }

  void _onScroll() {
    // Load more when near top (inverted list)
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      final state = context.read<NearbyGroupChatBloc>().state;
      if (state.hasMore && !state.isLoading) {
        _isLoadingMore = true;
        context
            .read<NearbyGroupChatBloc>()
            .add(const LoadMoreNearbyGroupMessages());
      }
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<NearbyGroupChatBloc>().add(SendNearbyGroupMessage(text));
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

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<NearbyGroupBloc, NearbyGroupState>(
          builder: (context, state) {
            final group = state.selectedGroup;
            if (group == null) {
              return const Text('Nearby Group');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${group.memberCount} nearby',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          BlocBuilder<NearbyGroupBloc, NearbyGroupState>(
            builder: (context, state) {
              return IconButton(
                icon: Badge(
                  label: Text('${state.groupMembers.length}'),
                  child: const Icon(Icons.people),
                ),
                onPressed: () => _showMembersSheet(context, state),
                tooltip: 'View members',
              );
            },
          ),
          // Delete button for group creator
          BlocBuilder<NearbyGroupBloc, NearbyGroupState>(
            builder: (context, state) {
              final authState = context.read<AuthBloc>().state;
              final group = state.selectedGroup;
              if (authState is! AuthAuthenticated || group == null) {
                return const SizedBox.shrink();
              }
              // Only show delete button for creator
              if (group.creatorId != authState.user.id) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                onPressed: () => _showDeleteConfirmation(context, group.id, authState.user.id),
                tooltip: 'Delete group',
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<NearbyGroupChatBloc, NearbyGroupChatState>(
        listener: (context, state) {
          // Reset loading more flag
          if (!state.isLoading) {
            _isLoadingMore = false;
          }

          // Handle access denial - navigate away with error
          if (state.hasError && !state.membershipVerified) {
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
              context.go(Routes.nearbyGroups);
            }
            return;
          }

          // Show other errors
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
                    'Verifying proximity...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          // SECURITY: Show access denied state for non-members
          if (state.hasError && !state.membershipVerified) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bluetooth_disabled,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Not In Range',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.errorMessage ?? 'Move closer to the group creator to join.',
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
                        context.go(Routes.nearbyGroups);
                      }
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          // Only show loading spinner during initial load (not when sending)
          if (state.status == NearbyGroupChatStatus.loading && 
              state.messages.isEmpty && 
              !state.isSending) {
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

              // Input area (only show if membership verified)
              if (state.membershipVerified) _buildInputArea(theme, state),
            ],
          );
        },
      ),
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

  Widget _buildMessagesList(NearbyGroupChatState state) {
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

  bool _shouldShowSenderInfo(NearbyGroupChatState state, int index) {
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

  Widget _buildInputArea(ThemeData theme, NearbyGroupChatState state) {
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

  void _showMembersSheet(BuildContext context, NearbyGroupState state) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nearby Members',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Members are auto-joined when detected via Bluetooth',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (state.groupMembers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No members detected')),
              )
            else
              ...state.groupMembers.map((member) => ListTile(
                    leading: CachedAvatar(
                      imageUrl: member.photoUrl,
                      name: member.displayName ?? member.username,
                      radius: 20,
                    ),
                    title: Text(member.displayName ?? member.username),
                    subtitle: Text('@${member.username}'),
                    trailing: member.isCurrentlyPresent
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Nearby',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.green,
                              ),
                            ),
                          )
                        : Text(
                            'Last seen ${_formatLastSeen(member.lastSeenAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                  )),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, String groupId, String userId) {
    final theme = Theme.of(context);
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<NearbyGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Group?'),
        content: const Text(
          'This will permanently delete the group, remove all members, '
          'and erase all chat messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(CloseNearbyGroup(
                    groupId: groupId,
                    userId: userId,
                  ));
              // Navigate back to nearby groups list
              context.go(Routes.nearbyGroups);
            },
            child: const Text('Delete Group'),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _MessageBubble extends StatelessWidget {
  final NearbyGroupMessage message;
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
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
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
                  if (!isMe && showSenderInfo && (message.senderName != null || message.senderUsername != null))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName ?? message.senderUsername ?? 'Unknown',
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
                                    ? theme.colorScheme
                                        .onPrimaryContainer
                                        .withValues(alpha: 0.5)
                                    : theme.colorScheme
                                        .onSurface
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
