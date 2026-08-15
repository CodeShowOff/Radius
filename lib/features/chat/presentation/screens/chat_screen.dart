import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/notifications/notification_service.dart';
import '../../../../core/services/presence/presence_service.dart';
import '../../../../core/services/realtime/realtime_connection_service.dart';
import '../../../../core/services/realtime/realtime_data_manager.dart';
import '../../../connections/data/connection_service.dart';
import '../../../connections/domain/entities/connection.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../data/audio_session_manager.dart';
import '../../data/chat_service.dart';

import '../bloc/chat_bloc.dart';
import '../bloc/conversations_bloc.dart';
import '../widgets/chat_input.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' hide Message, ChatState;
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:file_picker/file_picker.dart';
import 'photo_viewer_screen.dart';
import 'video_viewer_screen.dart';

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

/// CRITICAL: Implements WidgetsBindingObserver for app lifecycle handling.
/// This ensures messages sync correctly when:
/// - App returns from background
/// - App resumes from pause
/// - Device wakes from sleep
class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {

  Connection? _connection;

  String? _currentUserName;
  String? _currentUserPhotoUrl;

  // Global audio session manager — ensures only one audio plays at a time
  late final AudioSessionManager _audioSessionManager;

  // Presence tracking
  PresenceState? _otherUserPresence;
  StreamSubscription<Map<String, PresenceState>>? _presenceSubscription;
  
  // Reconnection subscription for network restore
  StreamSubscription<void>? _reconnectionSubscription;

  @override
  void initState() {
    super.initState();

    // CRITICAL FIX: Set conversation context IMMEDIATELY to prevent race condition
    // This must be the FIRST operation to ensure no notifications slip through
    // while the screen is initializing
    try {
      getIt<NotificationService>()
          .setCurrentConversation(widget.conversationId);
    } catch (_) {
      // Ignore if service not available
    }

    // CRITICAL: Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    _audioSessionManager = AudioSessionManager();
    _checkConnectionStatus();
    _initPresenceTracking();
    _initReconnectionHandling();

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

    // Tell ConversationsBloc which chat is active so it can exclude it
    // from the total unread badge count (prevents badge flash on incoming
    // messages while the user is viewing the chat).
    context.read<ConversationsBloc>().add(
          ConversationsSetActiveChat(conversationId: widget.conversationId),
        );
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

  /// Initialize handling for network reconnection events.
  /// When network is restored, we resync to ensure messages are received.
  void _initReconnectionHandling() {
    try {
      final connectionService = getIt<RealTimeDataManager>();
      _reconnectionSubscription = connectionService
          .connectionStatusStream
          .where((status) => status == RealtimeConnectionStatus.connected)
          .listen((_) {
        // Network reconnected - trigger resync
        if (mounted) {
          try {
            final bloc = _chatBloc ?? context.read<ChatBloc>();
            if (!bloc.isClosed) {
              bloc.add(const ChatResync());
            }
          } catch (_) {
            // BLoC not available or closed
          }
        }
      });
    } catch (_) {
      // Service not available
    }
  }

  ChatBloc? _chatBloc;
  ConversationsBloc? _conversationsBloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache the BLoC references for safe disposal. Assign only once to avoid
    // LateInitializationError when dependencies change multiple times.
    // CRITICAL: context.read() is unreliable in dispose() because the element
    // may already be deactivated. Caching here ensures we can always dispatch
    // events during teardown.
    _chatBloc ??= context.read<ChatBloc>();
    _conversationsBloc ??= context.read<ConversationsBloc>();
  }

  /// CRITICAL: Handle app lifecycle changes for reliable message delivery.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - resync to get any missed messages
        // Guard: bloc may have been closed during background
        if (_chatBloc != null && !_chatBloc!.isClosed) {
          _chatBloc!.add(const ChatResync());
        }
        // Re-assert notification context in case in-memory state was lost
        // (e.g., after process restart or long background pause)
        try {
          getIt<NotificationService>()
              .setCurrentConversation(widget.conversationId);
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

  @override
  void dispose() {
    // CRITICAL: Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    _audioSessionManager.dispose();
    
    // Cancel reconnection subscription
    _reconnectionSubscription?.cancel();
    
    // Stop watching presence
    _presenceSubscription?.cancel();
    try {
      getIt<RealTimeDataManager>().presenceService?.unwatchPresence(widget.otherUserId);
    } catch (_) {}

    // Notify notification service that user left this conversation
    try {
      getIt<NotificationService>().clearCurrentConversation(widget.conversationId);
    } catch (_) {
      // Ignore if service not available
    }

    // Clear active chat so its unread count is included in badge again.
    // By this time, markConversationAsRead has already reset the count to 0.
    // CRITICAL: Use cached reference instead of context.read() which is
    // unreliable in dispose() — the element may already be deactivated,
    // causing activeConversationId to remain stuck and permanently zeroing
    // out that conversation's unread count on every stream update.
    // Also guard against adding events after bloc is closed.
    if (_conversationsBloc != null && !_conversationsBloc!.isClosed) {
      _conversationsBloc!.add(
        const ConversationsSetActiveChat(conversationId: null),
      );
    }

    // Use cached reference to avoid context access after disposal.
    if (_chatBloc != null && !_chatBloc!.isClosed) {
      _chatBloc!.add(const ChatClose());
    }
    super.dispose();
  }

  void _sendMessage(String text) {
    context.read<ChatBloc>().add(ChatSendMessage(text));
  }

  void _onImageSelected(File file, ImageSource source) {
    context.read<ChatBloc>().add(ChatSendImage(file, source: source));
  }

  void _onDocumentSelected(File file) {
    context.read<ChatBloc>().add(ChatSendDocument(file));
  }

  void _handleAttachmentPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleImageSelection(ImageSource.camera);
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Camera'),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleImageSelection(ImageSource.gallery);
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Photo'),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleFileSelection();
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Document'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleImageSelection(ImageSource source) async {
    final result = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
    );
    if (result != null) {
      _onImageSelected(File(result.path), source);
    }
  }

  void _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      _onDocumentSelected(File(result.files.single.path!));
    }
  }

  void _handleMessageTap(BuildContext context, types.Message message) async {
    if (message is types.ImageMessage) {
      final heroTag = 'chat_image_${message.id}';
      Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) =>
              PhotoViewerScreen(
            imageUrl: message.uri.startsWith('http') ? message.uri : null,
            localFilePath: message.uri.startsWith('http') ? null : message.uri,
            heroTag: heroTag,
            caption: null,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else if (message is types.VideoMessage) {
      Navigator.push(
        context,
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (context, animation, secondaryAnimation) =>
              VideoViewerScreen(
            videoUrl: message.uri,
            caption: null,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
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
            // Messages list and input handled by Chat widget
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  // Show error state if completely failed (no messages)
                  if (state.status == ChatStatus.error && state.messages.isEmpty) {
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

                  return Chat(
                    messages: state.chatUiMessages,
                    onAttachmentPressed: (isDisconnected || isBlocked) ? null : _handleAttachmentPressed,
                    onMessageTap: _handleMessageTap,
                    onMessageLongPress: _handleMessageLongPress,
                    timeFormat: DateFormat.jm(),
                    dateFormat: DateFormat('MMMM d, yyyy'),
                    onSendPressed: (types.PartialText message) {},
                    customBottomWidget: (isDisconnected || isBlocked) ? const SizedBox.shrink() : _buildInputArea(Theme.of(context), state),
                    user: types.User(id: widget.currentUserId),
                    onEndReached: () async {
                      if (state.hasMore && state.status != ChatStatus.loadingMore) {
                        context.read<ChatBloc>().add(const ChatLoadMore());
                      }
                    },
                    theme: DefaultChatTheme(
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      primaryColor: Theme.of(context).colorScheme.primary,
                    ),
                    typingIndicatorOptions: TypingIndicatorOptions(
                      typingUsers: state.isOtherUserTyping ? [types.User(id: widget.otherUserId, firstName: widget.otherUserName)] : [],
                    ),
                  );
                },
              ),
            ),
            if (isDisconnected || isBlocked)
              Container(
                width: double.infinity,
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

  Widget _buildInputArea(ThemeData theme, ChatState state) {
    return ChatInput(
      onSend: (text) {
        _sendMessage(text);
      },
      onImageSelected: (file) {
        context.read<ChatBloc>().add(ChatSendImage(file, source: ImageSource.gallery));
      },
      onCameraImageSelected: (file) {
        context.read<ChatBloc>().add(ChatSendImage(file, source: ImageSource.camera));
      },
      onDocumentSelected: (file) {
        context.read<ChatBloc>().add(ChatSendDocument(file));
      },
      onVideoSelected: (file) {
        context.read<ChatBloc>().add(ChatSendVideo(file));
      },
      onVoiceRecorded: (file, duration) {
        context.read<ChatBloc>().add(ChatSendAudio(file, duration: duration));
      },
    );
  }

  void _handleMessageLongPress(BuildContext context, types.Message message) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message is types.TextMessage)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy Text'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(bottomSheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
              if (message.author.id == widget.currentUserId)
                ListTile(
                  leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                  title: Text('Delete Message', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    context.read<ChatBloc>().add(ChatDeleteMessage(message.id));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    switch (action) {
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
          'This will permanently delete all messages for both users.',
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
                    ConnectionBlockUser(
                      widget.otherUserId,
                      blockedName: widget.otherUserName,
                    ),
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
    // For last seen in dark mode, use white color
    if (theme.brightness == Brightness.dark) {
      return Colors.white;
    }
    final baseColor = theme.textTheme.bodySmall?.color;
    return baseColor?.withValues(alpha: 0.7);
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
            if (!isDisconnected && !isBlocked) ...[
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


