import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/services/presence/presence_service.dart';
import '../../../../core/services/realtime/realtime_data_manager.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/domain/entities/connection.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../data/chat_service.dart';
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
  Connection? _connection;

  String? _currentUserName;
  String? _currentUserPhotoUrl;

  // Presence tracking
  PresenceState? _otherUserPresence;
  StreamSubscription<Map<String, PresenceState>>? _presenceSubscription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _checkConnectionStatus();
    _initPresenceTracking();

    // Cache current user's profile info (used when creating a new conversation).
    try {
      final profileState = context.read<ProfileBloc>().state;
      if (profileState is ProfileLoaded) {
        _currentUserName = profileState.profile.name;
        _currentUserPhotoUrl = profileState.profile.photoUrl;
      }
    } catch (_) {
      // ProfileBloc may not be available in some navigation flows.
    }

    // Notify notification service that user is viewing this conversation
    try {
      getIt<NotificationService>()
          .setCurrentConversation(widget.conversationId);
    } catch (_) {
      // Ignore if service not available
    }

    // Open the chat
    context.read<ChatBloc>().add(ChatOpen(
          conversationId: widget.conversationId,
          currentUserId: widget.currentUserId,
          currentUserName: _currentUserName,
          currentUserPhotoUrl: _currentUserPhotoUrl,
          otherUserId: widget.otherUserId,
          otherUserName: widget.otherUserName,
          otherUserPhotoUrl: widget.otherUserPhotoUrl,
        ));
  }

  /// Initialize presence tracking for the other user.
  void _initPresenceTracking() {
    try {
      final presenceService = getIt<RealTimeDataManager>().presenceService;
      if (presenceService == null) return;

      // Start watching the other user's presence
      presenceService.watchPresence(widget.otherUserId);

      // Listen for presence updates
      _presenceSubscription = presenceService.presenceUpdates.listen((updates) {
        final presence = updates[widget.otherUserId];
        if (mounted && presence != _otherUserPresence) {
          setState(() {
            _otherUserPresence = presence;
          });
        }
      });

      // Get initial presence state
      presenceService.getPresence(widget.otherUserId).then((presence) {
        if (mounted) {
          setState(() {
            _otherUserPresence = presence;
          });
        }
      });
    } catch (_) {
      // Presence service not available
    }
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

  ChatBloc? _chatBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC reference for safe disposal. Assign only once to avoid
    // LateInitializationError when dependencies change multiple times.
    _chatBloc ??= context.read<ChatBloc>();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    
    // Stop watching presence
    _presenceSubscription?.cancel();
    try {
      getIt<RealTimeDataManager>().presenceService?.unwatchPresence(widget.otherUserId);
    } catch (_) {}

    // Notify notification service that user left this conversation
    try {
      getIt<NotificationService>().clearCurrentConversation();
    } catch (_) {
      // Ignore if service not available
    }

    // Use cached reference to avoid context access after disposal
    _chatBloc?.add(const ChatClose());
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

  void _onImageSelected(File file, ImageSource source) {
    context.read<ChatBloc>().add(ChatSendImage(file, source: source));
    _scrollToBottom();
  }

  void _onDocumentSelected(File file) {
    context.read<ChatBloc>().add(ChatSendDocument(file));
    _scrollToBottom();
  }

  void _onVoiceRecorded(File file, int duration) {
    context.read<ChatBloc>().add(ChatSendAudio(file, duration: duration));
    _scrollToBottom();
  }

  void _scrollToBottom() {
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

    return BlocListener<ChatBloc, ChatState>(
      listener: (context, state) {
        // Show SnackBar for transient errors (like upload failures)
        if (state.errorMessage != null && state.status != ChatStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: Theme.of(context).colorScheme.error,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Theme.of(context).colorScheme.onError,
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (prev, curr) =>
                prev.otherUserName != curr.otherUserName ||
                prev.otherUserPhotoUrl != curr.otherUserPhotoUrl ||
                prev.conversation != curr.conversation,
            builder: (context, state) {
              final effectiveName =
                  (state.otherUserName?.trim().isNotEmpty == true)
                      ? state.otherUserName!.trim()
                      : widget.otherUserName;
              final effectivePhotoUrl =
                  (state.otherUserPhotoUrl?.trim().isNotEmpty == true)
                      ? state.otherUserPhotoUrl!.trim()
                      : widget.otherUserPhotoUrl;
              final isMuted = state.conversation?.isMutedBy(widget.currentUserId) ?? false;

              return _ChatAppBar(
                name: effectiveName,
                photoUrl: effectivePhotoUrl,
                presenceState: _otherUserPresence,
                isTyping: state.isOtherUserTyping,
                onBackPressed: () => Navigator.of(context).pop(),
                onProfileTap: () {
                  context.push(
                    Routes.userProfileWith(widget.otherUserId),
                    extra: {
                      'displayName': effectiveName,
                      'photoUrl': effectivePhotoUrl,
                    },
                  );
                },
                onMenuSelected: (value) => _handleMenuAction(context, value),
                isDisconnected: isDisconnected,
                isBlocked: isBlocked,
                isMuted: isMuted,
              );
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Disconnection banner
              if (isDisconnected)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  // Show error state
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
                                    currentUserName: _currentUserName,
                                    currentUserPhotoUrl: _currentUserPhotoUrl,
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

                  // KEY FIX: Only show full-screen spinner on FIRST load (no cached messages).
                  // If we have cached messages from a previous session, show them immediately
                  // while the stream reconnects in the background.
                  final hasMessages = state.allMessages.isNotEmpty;
                  final isInitialLoading = state.status == ChatStatus.loading && !hasMessages;
                  
                  if (isInitialLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  // Show messages list (may be empty for new conversations)
                  // The _MessagesList handles empty state internally
                  return _MessagesList(
                    messages: state.allMessages,
                    currentUserId: state.currentUserId ?? widget.currentUserId,
                    isTyping: state.isOtherUserTyping,
                    hasMore: state.hasMore,
                    scrollController: _scrollController,
                    // Pass loading state so list can show subtle indicator
                    isLoading: state.status == ChatStatus.loading,
                  );
                },
              ),
            ),

            // Input
            if (!isDisconnected && !isBlocked)
              ChatInput(
                onSend: _sendMessage,
                onTypingChanged: _onTypingChanged,
                onImageSelected: (file) =>
                    _onImageSelected(file, ImageSource.gallery),
                onCameraImageSelected: (file) =>
                    _onImageSelected(file, ImageSource.camera),
                onDocumentSelected: _onDocumentSelected,
                onVoiceRecorded: _onVoiceRecorded,
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
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
      case 'delete':
        _confirmDeleteConversation(context);
        break;
      case 'mute':
        _toggleMute(context);
        break;
      case 'clear':
        _confirmClearChat(context);
        break;
      case 'block':
        _confirmBlockUser(context);
        break;
      case 'unblock':
        _confirmUnblockUser(context);
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

              try {
                // Delete conversation directly via chat service
                await getIt<ChatService>().deleteConversation(
                  widget.conversationId,
                  widget.currentUserId,
                );

                // Go back to conversations list
                if (context.mounted) {
                  Navigator.of(context).pop();

                  // Show confirmation
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Conversation deleted'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
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

  void _toggleMute(BuildContext context) async {
    final chatState = context.read<ChatBloc>().state;
    final currentMuteStatus = chatState.conversation?.isMutedBy(widget.currentUserId) ?? false;
    final newMuteStatus = !currentMuteStatus;
    
    try {
      // Toggle mute status via chat service
      await getIt<ChatService>().setMuted(
        conversationId: widget.conversationId,
        userId: widget.currentUserId,
        muted: newMuteStatus,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newMuteStatus ? 'Notifications muted' : 'Notifications unmuted'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update mute status: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _confirmClearChat(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: const Text(
          'This will delete all messages in this chat. '
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

              // Clear chat via bloc
              context.read<ChatBloc>().add(const ChatClear());

              // Show confirmation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chat cleared'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _confirmBlockUser(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block User?'),
        content: Text(
          'Blocking ${widget.otherUserName} will prevent them from sending you messages. '
          'You can unblock them later from settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Block user via connections bloc
              context.read<ConnectionBloc>().add(
                    ConnectionBlockUser(widget.otherUserId),
                  );

              // Wait a bit for the operation to propagate
              await Future.delayed(const Duration(milliseconds: 500));

              // Go back since chat is now blocked
              if (context.mounted) {
                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${widget.otherUserName} has been blocked'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _confirmUnblockUser(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unblock User?'),
        content: Text(
          'Unblocking ${widget.otherUserName} will allow them to send you messages again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Unblock user via connections bloc
              context.read<ConnectionBloc>().add(
                    ConnectionUnblockUser(widget.otherUserId),
                  );

              // Wait for the operation to complete
              await Future.delayed(const Duration(milliseconds: 500));

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${widget.otherUserName} has been unblocked'),
                    duration: const Duration(seconds: 2),
                  ),
                );

                // Refresh connection status
                _checkConnectionStatus();
              }
            },
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String name;
  final String? photoUrl;
  final PresenceState? presenceState;
  final bool isTyping;
  final VoidCallback onBackPressed;
  final VoidCallback onProfileTap;
  final void Function(String) onMenuSelected;
  final bool isDisconnected;
  final bool isBlocked;
  final bool isMuted;

  const _ChatAppBar({
    required this.name,
    this.photoUrl,
    this.presenceState,
    this.isTyping = false,
    required this.onBackPressed,
    required this.onProfileTap,
    required this.onMenuSelected,
    this.isDisconnected = false,
    this.isBlocked = false,
    this.isMuted = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// Get the subtitle text for the app bar (typing > online status > last seen).
  String? _getSubtitleText() {
    if (isTyping) {
      return 'typing...';
    }
    if (presenceState != null) {
      return presenceState!.displayText;
    }
    return null;
  }

  /// Get the color for the subtitle text.
  Color? _getSubtitleColor(ThemeData theme) {
    if (isTyping) {
      return theme.colorScheme.primary;
    }
    if (presenceState?.isOnline == true) {
      return Colors.green;
    }
    final baseColor = theme.textTheme.bodySmall?.color;
    return baseColor != null
        ? Color.fromRGBO(baseColor.r.toInt(), baseColor.g.toInt(), baseColor.b.toInt(), 0.7)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleText = _getSubtitleText();
    final subtitleColor = _getSubtitleColor(theme);

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBackPressed,
      ),
      title: InkWell(
        onTap: onProfileTap,
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            // Avatar with online indicator
            Stack(
              children: [
                CachedAvatar(
                  imageUrl: photoUrl,
                  name: name,
                  radius: 18,
                ),
                // Online indicator dot
                if (presenceState?.isOnline == true)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
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
                  // Online status / typing indicator / last seen
                  if (subtitleText != null)
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                        fontWeight: isTyping ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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
            else ...[
              PopupMenuItem(
                value: 'mute',
                child: Text(isMuted ? 'Unmute notifications' : 'Mute notifications'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat'),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Text('Block user'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete conversation'),
              ),
            ],
            if (isBlocked) ...[
              const PopupMenuItem(
                value: 'unblock',
                child: Text('Unblock user'),
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
  final bool isLoading;

  const _MessagesList({
    required this.messages,
    required this.currentUserId,
    required this.isTyping,
    required this.hasMore,
    required this.scrollController,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    // Only show empty state if:
    // 1. Not loading (stream has emitted at least once)
    // 2. No messages
    // 3. No typing indicator
    // This prevents the "No messages yet" flash during initial load
    if (messages.isEmpty && !isTyping && !isLoading) {
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
    
    // If loading with no messages yet, show nothing (parent handles spinner)
    if (messages.isEmpty && isLoading) {
      return const SizedBox.shrink();
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
