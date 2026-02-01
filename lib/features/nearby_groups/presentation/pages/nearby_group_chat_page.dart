import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/nearby_group_message.dart';
import '../bloc/nearby_group_bloc.dart';
import '../bloc/nearby_group_chat_bloc.dart';

/// Chat page for nearby groups.
///
/// Features:
/// - Real-time messaging
/// - Member presence indicator
/// - Auto-joined via Bluetooth (no explicit join)
/// - Membership verification on load
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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatBloc ??= context.read<NearbyGroupChatBloc>();
    
    // Initialize only once after dependencies are available
    if (!_initialized) {
      _initialized = true;
      _loadGroupDetails();
      _openChat();
    }
  }

  void _loadGroupDetails() {
    context.read<NearbyGroupBloc>().add(LoadNearbyGroupDetails(widget.groupId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _chatBloc?.add(const ResyncNearbyGroupChat());
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
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _focusNode.dispose();
    _chatBloc?.add(const CloseNearbyGroupChat());
    super.dispose();
  }

  void _onScroll() {
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
        ],
      ),
      body: Column(
        children: [
          // Membership status banner
          BlocBuilder<NearbyGroupChatBloc, NearbyGroupChatState>(
            buildWhen: (prev, curr) =>
                prev.membershipVerified != curr.membershipVerified ||
                prev.status != curr.status,
            builder: (context, state) {
              if (!state.membershipVerified &&
                  state.status != NearbyGroupChatStatus.loading) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: theme.colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(
                        Icons.bluetooth_disabled,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Move closer to the group creator to join',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // Messages list
          Expanded(
            child: BlocConsumer<NearbyGroupChatBloc, NearbyGroupChatState>(
              listener: (context, state) {
                if (state.status == NearbyGroupChatStatus.loaded) {
                  _isLoadingMore = false;
                }
                if (state.errorMessage != null &&
                    state.status == NearbyGroupChatStatus.error) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.errorMessage!),
                      backgroundColor: theme.colorScheme.error,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state.status == NearbyGroupChatStatus.loading &&
                    state.messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.5),
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
                            color: theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  );
                }

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
              },
            ),
          ),

          // Input field
          BlocBuilder<NearbyGroupChatBloc, NearbyGroupChatState>(
            buildWhen: (prev, curr) =>
                prev.membershipVerified != curr.membershipVerified,
            builder: (context, state) {
              final canSend = state.membershipVerified;

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
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        enabled: canSend,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: canSend
                              ? 'Message...'
                              : 'Move closer to send messages',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: canSend ? (_) => _sendMessage() : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: canSend ? _sendMessage : null,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
                              color: Colors.green.withOpacity(0.2),
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

  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      message.senderName ?? message.senderUsername ?? 'Unknown',
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
                          ? theme.colorScheme.onPrimary.withOpacity(0.7)
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
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
