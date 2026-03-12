import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/widgets/group_message_bubble.dart';
import '../../../../core/widgets/pending_requests_sheet.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/data/audio_session_manager.dart';
import '../../../chat/presentation/widgets/chat_input.dart';
import '../../../location_groups/domain/entities/group_message.dart';
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
  final ScrollController _scrollController = ScrollController();
  final AudioSessionManager _audioSessionManager = AudioSessionManager();
  bool _isLoadingMore = false;
  RandomGroupChatBloc? _chatBloc;
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

  /// Scrolls to the first unread message position.
  void _scrollToFirstUnread(RandomGroupChatState state) {
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

              // Clear messages from UI immediately for instant feedback.
              // The isClearingChat flag in chat bloc prevents the Firestore
              // stream from re-populating messages during batch soft-delete.
              chatBloc.add(const ClearRandomGroupChatMessages());

              // Clear messages from backend (will also trigger stream update).
              // Listen for result via _handleClearChatResult.
              randomGroupBloc.add(ClearRandomGroupChat(
                groupId: widget.groupId,
                adminUserId: authState.user.id,
              ));

              // Don't show snackbar here — wait for backend result.
              // Success/error is handled by the BlocListener for RandomGroupBloc.
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

    return BlocListener<RandomGroupBloc, RandomGroupState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage ||
          previous.status != current.status,
      listener: (context, groupState) {
        // Handle clear chat result from backend
        final chatState = context.read<RandomGroupChatBloc>().state;
        if (chatState.isClearingChat) {
          if (groupState.errorMessage != null) {
            // Backend clear failed — re-open chat to restore messages
            // from the Firestore stream (messages weren't actually deleted)
            _openChat();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(groupState.errorMessage!),
                backgroundColor: theme.colorScheme.error,
                duration: const Duration(seconds: 3),
              ),
            );
          } else if (groupState.status == RandomGroupBlocStatus.loaded) {
            // Backend clear succeeded (loaded state, no error)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Chat cleared'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
      child: BlocBuilder<RandomGroupBloc, RandomGroupState>(
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
            listenWhen: (previous, current) =>
                previous.status != current.status ||
                (current.firstUnreadMessageId != null &&
                    previous.firstUnreadMessageId == null),
            listener: (context, state) {
              // Reset loading more flag
              if (state.status != RandomGroupChatStatus.loading) {
                _isLoadingMore = false;
              }

              // Scroll to first unread message on initial load
              if (!_hasScrolledToUnread &&
                  state.firstUnreadMessageId != null) {
                _hasScrolledToUnread = true;
                _scrollToFirstUnread(state);
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
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(RandomGroupChatState state) {
    final messages = state.allMessages;
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      itemCount: messages.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
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
              senderName: message.senderName ?? message.senderUsername,
              senderPhotoUrl: message.senderPhotoUrl,
              sentAt: message.sentAt,
              status: message.status,
              isDeleted: message.isDeleted,
              messageType: _mapMessageType(message.type),
              mediaUrl: message.mediaUrl,
              mediaFileName: message.mediaFileName,
              mediaFileSize: message.mediaFileSize,
              duration: message.duration,
              thumbnailUrl: message.thumbnailUrl,
              uploadProgress: message.uploadProgress,
              audioSessionManager: _audioSessionManager,
              onSenderTap: message.senderId != null
                  ? () => context.push(
                        Routes.userProfileWith(message.senderId!),
                        extra: {
                          'displayName': message.senderName ?? message.senderUsername,
                          'photoUrl': message.senderPhotoUrl,
                        },
                      )
                  : null,
              onRetry: message.canRetry && message.localId != null
                  ? () => context.read<RandomGroupChatBloc>().add(
                        RetryRandomGroupMessage(message.localId!),
                      )
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

  Widget _buildInputArea(ThemeData theme, RandomGroupChatState state) {
    return ChatInput(
      onSend: (text) {
        context.read<RandomGroupChatBloc>().add(SendRandomGroupMessage(text));
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
        context.read<RandomGroupChatBloc>().add(SendRandomGroupImage(file));
      },
      onCameraImageSelected: (file) {
        context.read<RandomGroupChatBloc>().add(SendRandomGroupImage(file));
      },
      onDocumentSelected: (file) {
        context.read<RandomGroupChatBloc>().add(SendRandomGroupDocument(file));
      },
      onVideoSelected: (file) {
        context.read<RandomGroupChatBloc>().add(SendRandomGroupVideo(file));
      },
      onVoiceRecorded: (file, duration) {
        context
            .read<RandomGroupChatBloc>()
            .add(SendRandomGroupAudio(file, duration: duration));
      },
      showVideoComingSoon: true,
    );
  }

  /// Maps [RandomGroupMessageType] to [GroupMessageType] for the shared bubble widget.
  static GroupMessageType _mapMessageType(RandomGroupMessageType type) {
    switch (type) {
      case RandomGroupMessageType.text:
        return GroupMessageType.text;
      case RandomGroupMessageType.system:
        return GroupMessageType.system;
      case RandomGroupMessageType.image:
        return GroupMessageType.image;
      case RandomGroupMessageType.audio:
        return GroupMessageType.audio;
      case RandomGroupMessageType.document:
        return GroupMessageType.document;
      case RandomGroupMessageType.video:
        return GroupMessageType.video;
    }
  }
}
