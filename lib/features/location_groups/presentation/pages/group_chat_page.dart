import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/group_message_bubble.dart';
import '../../../../core/widgets/pending_requests_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/data/audio_session_manager.dart';
import '../../../chat/presentation/widgets/chat_input.dart';
import '../../domain/entities/group_message.dart';
import '../bloc/group_chat_bloc.dart';
import '../bloc/location_group_bloc.dart';

/// Page for group chat with real-time messaging.
///
/// CRITICAL: Implements [WidgetsBindingObserver] for app lifecycle handling.
/// This ensures messages sync correctly when:
/// - App returns from background
/// - App resumes from pause
/// - Device wakes from sleep
class GroupChatPage extends StatefulWidget {
  final String groupId;

  const GroupChatPage({
    super.key,
    required this.groupId,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final AudioSessionManager _audioSessionManager = AudioSessionManager();
  bool _isLoadingMore = false;
  GroupChatBloc? _chatBloc;
  bool _hasScrolledToUnread = false;

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
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    final bloc = context.read<LocationGroupBloc>();
    bloc.add(LoadGroupDetails(
      groupId: widget.groupId,
      currentUserId: userId,
    ));
    // Load join requests so admin can see badge for pending requests
    bloc.add(LoadJoinRequests(groupId: widget.groupId));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC reference for safe disposal
    _chatBloc ??= context.read<GroupChatBloc>();
  }

  /// CRITICAL: Handle app lifecycle changes for reliable message delivery.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - resync to get any missed messages
        _chatBloc?.add(const ResyncGroupChat());
        // Re-assert notification context in case in-memory state was lost
        try {
          getIt<NotificationService>().setCurrentGroup(widget.groupId);
        } catch (_) {}
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
    // CRITICAL: Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _audioSessionManager.dispose();

    // Notify notification service that user left this group
    try {
      getIt<NotificationService>().clearCurrentGroup(widget.groupId);
    } catch (_) {
      // Ignore if service not available
    }

    // Use cached reference to avoid context access after disposal
    _chatBloc?.add(const CloseGroupChat());
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

  /// Scrolls to the first unread message position.
  void _scrollToFirstUnread(GroupChatState state) {
    final messages = state.allMessages;
    final firstUnreadIndex = messages.indexWhere(
      (m) => m.id == state.firstUnreadMessageId,
    );

    // If unread message is near the bottom (within first 3 items), no scroll needed
    if (firstUnreadIndex <= 2) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;

      // Estimate offset: index * average message height (70px)
      final estimatedOffset = (firstUnreadIndex - 1) * 70.0;
      final targetOffset = estimatedOffset.clamp(0.0, maxExtent);

      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  void _confirmClearChat() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    // Capture the blocs before showing dialog to ensure they're accessible
    final locationGroupBloc = context.read<LocationGroupBloc>();
    final chatBloc = context.read<GroupChatBloc>();

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
              chatBloc.add(const ClearGroupChatMessages());

              // Clear messages from backend (will also trigger stream update)
              locationGroupBloc.add(ClearGroupChat(
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
      BuildContext context, LocationGroupState groupState) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final bloc = context.read<LocationGroupBloc>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (modalContext) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<LocationGroupBloc, LocationGroupState>(
          builder: (builderContext, state) {
            final requests = state.joinRequests
                .map((r) => PendingRequestItem(
                      id: r.id,
                      userId: r.userId,
                      displayName: r.userName ?? 'Unknown User',
                      photoUrl: r.userPhotoUrl,
                      message: r.message,
                      requestedAt: r.requestedAt,
                    ))
                .toList();

            return PendingRequestsSheet(
              requests: requests,
              onApprove: (request) {
                builderContext.read<LocationGroupBloc>().add(ApproveJoinRequest(
                      groupId: widget.groupId,
                      requestUserId: request.userId,
                      adminUserId: authState.user.id,
                    ));
              },
              onReject: (request) {
                builderContext.read<LocationGroupBloc>().add(RejectJoinRequest(
                      groupId: widget.groupId,
                      requestUserId: request.userId,
                      adminUserId: authState.user.id,
                    ));
              },
              onAcceptAll: () {
                builderContext
                    .read<LocationGroupBloc>()
                    .add(ApproveAllJoinRequests(
                      groupId: widget.groupId,
                      adminUserId: authState.user.id,
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

    return BlocBuilder<LocationGroupBloc, LocationGroupState>(
      builder: (context, groupState) {
        final group = groupState.currentGroup;
        final groupName = group?.name ?? 'Group Chat';
        final hasPendingRequests =
            groupState.isAdmin && groupState.joinRequests.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: InkWell(
              onTap: () {
                if (hasPendingRequests) {
                  _showPendingRequestsSheet(context, groupState);
                } else {
                  context.push(
                    Routes.locationGroupDetailWith(widget.groupId),
                  );
                }
              },
              borderRadius: BorderRadius.circular(24),
              child: Row(
                children: [
                  CachedAvatar(
                    imageUrl: group?.avatarUrl,
                    name: groupName,
                    radius: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      groupName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Show dot badge for pending requests (admin only)
              if (hasPendingRequests)
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
                  Routes.locationGroupDetailWith(widget.groupId),
                ),
                icon: const Icon(Icons.info_outline),
                tooltip: 'Group Info',
              ),
              if (groupState.isAdmin)
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
          body: BlocConsumer<GroupChatBloc, GroupChatState>(
            listenWhen: (previous, current) =>
                previous.status != current.status ||
                (current.firstUnreadMessageId != null &&
                    previous.firstUnreadMessageId == null),
            listener: (context, state) {
              // Reset loading more flag
              if (!state.isLoading) {
                _isLoadingMore = false;
              }

              // Scroll to first unread message on initial load
              if (!_hasScrolledToUnread &&
                  state.firstUnreadMessageId != null) {
                _hasScrolledToUnread = true;
                _scrollToFirstUnread(state);
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
                  context.go(Routes.myGroups);
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
              // SECURITY: Show access denied state for non-members
              if (state.hasError && !state.membershipVerified) {
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
                            'You must be a member to access this chat.',
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
                            context.go(Routes.myGroups);
                          }
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Go Back'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  // Messages list
                  Expanded(
                    child: state.isLoading && state.allMessages.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : state.allMessages.isEmpty
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
    final messages = state.allMessages;
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      itemCount: messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the end (top when reversed)
        if (index == messages.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final message = messages[index];
        final isMe = message.senderId == state.currentUserId;
        final showSenderInfo = !isMe && _shouldShowSenderInfo(messages, index);

        // Check if this message is the first unread message
        final isFirstUnread = state.firstUnreadMessageId != null &&
            message.id == state.firstUnreadMessageId;

        return Column(
          children: [
            if (isFirstUnread)
              GroupUnreadDivider(count: state.unreadCountAtOpen),
            GroupMessageBubble(
              messageId: message.id,
              text: message.text,
              isMe: isMe,
              isSystemMessage: message.isSystemMessage,
              showSenderInfo: showSenderInfo,
              senderName: message.senderName,
              senderPhotoUrl: message.senderPhotoUrl,
              sentAt: message.sentAt,
              status: message.status,
              isDeleted: message.isDeleted,
              messageType: message.type,
              mediaUrl: message.mediaUrl,
              mediaFileName: message.mediaFileName,
              mediaFileSize: message.mediaFileSize,
              duration: message.duration,
              thumbnailUrl: message.thumbnailUrl,
              uploadProgress: message.uploadProgress,
              audioSessionManager: _audioSessionManager,
              onSenderTap: () => context.push(
                Routes.userProfileWith(message.senderId),
                extra: {
                  'displayName': message.senderName,
                  'photoUrl': message.senderPhotoUrl,
                },
              ),
              onRetry: message.canRetry && message.localId != null
                  ? () => context.read<GroupChatBloc>().add(
                        RetryGroupMessage(message.localId!),
                      )
                  : null,
              onDelete: isMe && !message.isPending
                  ? () => _confirmDelete(message)
                  : null,
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowSenderInfo(List messages, int index) {
    // Always show for first message (at the bottom visually)
    if (index == messages.length - 1) return true;

    final message = messages[index];
    final nextMessage = messages[index + 1];

    // Show if sender changed
    if (message.senderId != nextMessage.senderId) return true;

    // Show if there's a time gap of more than 5 minutes
    final timeDiff = message.sentAt.difference(nextMessage.sentAt);
    if (timeDiff.inMinutes > 5) return true;

    return false;
  }

  void _confirmDelete(GroupMessage message) {
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<GroupChatBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(DeleteGroupMessage(message.id));
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme, GroupChatState state) {
    return ChatInput(
      onSend: (text) {
        context.read<GroupChatBloc>().add(SendGroupMessage(text));
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
      },
      onImageSelected: (file) {
        context.read<GroupChatBloc>().add(SendGroupImage(file));
      },
      onCameraImageSelected: (file) {
        context.read<GroupChatBloc>().add(SendGroupImage(file));
      },
      onDocumentSelected: (file) {
        context.read<GroupChatBloc>().add(SendGroupDocument(file));
      },
      onVideoSelected: (file) {
        context.read<GroupChatBloc>().add(SendGroupVideo(file));
      },
      onVoiceRecorded: (file, duration) {
        context.read<GroupChatBloc>().add(SendGroupAudio(file, duration: duration));
      },
      showVideoComingSoon: true,
    );
  }
}
