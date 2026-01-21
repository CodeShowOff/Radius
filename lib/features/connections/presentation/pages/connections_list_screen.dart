import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/firebase/firestore_service.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../domain/entities/connection.dart';
import '../bloc/connection_bloc.dart';

/// Screen displaying user's connections list.
class ConnectionsListScreen extends StatefulWidget {
  const ConnectionsListScreen({super.key});

  @override
  State<ConnectionsListScreen> createState() => _ConnectionsListScreenState();
}

class _ConnectionsListScreenState extends State<ConnectionsListScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Connections'),
        actions: [
          BlocBuilder<ConnectionBloc, ConnectionBlocState>(
            builder: (context, state) {
              final pendingCount = state.receivedRequests.length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.mail_outline),
                    onPressed: () {
                      context.push(Routes.connectionRequests);
                    },
                    tooltip: 'Requests',
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          pendingCount > 9 ? '9+' : pendingCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<ConnectionBloc, ConnectionBlocState>(
        builder: (context, state) {
          if (state.status == ConnectionBlocStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          final connections = state.connections;

          if (connections.isEmpty) {
            return _EmptyConnectionsState(
              onFindPeople: () {
                context.push(Routes.nearby);
              },
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: connections.length,
              itemBuilder: (context, index) {
                final connection = connections[index];
                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 300 + (index * 50)),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(
                        opacity: value,
                        child: child,
                      ),
                    );
                  },
                  child: _ConnectionTile(
                    connection: connection,
                    currentUserId: state.userId!,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionTile extends StatefulWidget {
  final Connection connection;
  final String currentUserId;

  const _ConnectionTile({
    required this.connection,
    required this.currentUserId,
  });

  @override
  State<_ConnectionTile> createState() => _ConnectionTileState();
}

class _ConnectionTileState extends State<_ConnectionTile> {
  late final Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadOtherUserProfile();
  }

  Future<Map<String, dynamic>> _loadOtherUserProfile() async {
    final otherUserId = widget.connection.getOtherUserId(widget.currentUserId);
    try {
      final doc = await getIt<FirestoreService>()
          .getDocument('profiles/$otherUserId')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );

      if (doc == null) {
        return {
          'id': otherUserId,
          'name': 'User',
          'photoUrl': null,
          'bio': '',
          'vibe': '',
          'mood': '',
          'gender': null,
        };
      }

      // Prefer 'displayName' but fall back to legacy 'name'
      final rawName =
          (doc['displayName'] as String?) ?? (doc['name'] as String?);
      final name = rawName?.trim();
      final photoUrl = (doc['photoUrl'] as String?)?.trim();
      final bio = (doc['bio'] as String?)?.trim();
      final vibe = (doc['vibe'] as String?)?.trim();
      final mood = (doc['mood'] as String?)?.trim();
      final gender = (doc['gender'] as String?)?.trim();

      return {
        'id': otherUserId,
        'name': (name != null && name.isNotEmpty) ? name : 'User',
        'photoUrl': (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
        'bio': bio ?? '',
        'vibe': vibe ?? '',
        'mood': mood ?? '',
        'gender': gender,
      };
    } catch (_) {
      return {'id': otherUserId, 'name': 'User', 'photoUrl': null, 'bio': '', 'vibe': '', 'mood': '', 'gender': null};
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherUserId = widget.connection.getOtherUserId(widget.currentUserId);

    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final displayName = (profile?['name'] as String?)?.trim().isNotEmpty ==
                true
            ? (profile!['name'] as String).trim()
            : 'User';
        final photoUrl = (profile?['photoUrl'] as String?)?.trim().isNotEmpty ==
                true
            ? (profile!['photoUrl'] as String).trim()
            : null;
        final bio = (profile?['bio'] as String?)?.trim();
        final vibe = (profile?['vibe'] as String?)?.trim();
        final mood = (profile?['mood'] as String?)?.trim();

        return ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: photoUrl != null
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: photoUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  )
                : Text(
                    displayName[0].toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(displayName),
              ),
              if (vibe != null && vibe.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mood,
                        size: 12,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        vibe,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (mood != null && mood.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sentiment_satisfied_alt,
                        size: 12,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        mood,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          subtitle: (bio != null && bio.isNotEmpty)
              ? Text(
                  bio,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              : Text(
                  'Connected ${_formatDate(widget.connection.connectedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(
              context,
              value,
              otherUserId,
              otherUserName: displayName,
              otherUserPhotoUrl: photoUrl,
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'message',
                child: ListTile(
                  leading: Icon(Icons.message_outlined),
                  title: Text('Message'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  leading: Icon(Icons.person_remove_outlined),
                  title: Text('Remove'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'block',
                child: ListTile(
                  leading: Icon(
                    Icons.block,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Block',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          onTap: () {
            final conversationId = Conversation.createConversationId(
              widget.currentUserId,
              otherUserId,
            );
            context.push(
              Routes.chatWith(conversationId),
              extra: {
                'currentUserId': widget.currentUserId,
                'otherUserId': otherUserId,
                'otherUserName': displayName,
                'otherUserPhotoUrl': photoUrl,
              },
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()} weeks ago';
    } else {
      return '${(diff.inDays / 30).floor()} months ago';
    }
  }

  void _handleMenuAction(
    BuildContext context,
    String action,
    String otherUserId, {
    required String otherUserName,
    required String? otherUserPhotoUrl,
  }) {
    switch (action) {
      case 'message':
        // Create conversation ID and navigate to chat
        final conversationId =
            Conversation.createConversationId(widget.currentUserId, otherUserId);
        context.push(
          Routes.chatWith(conversationId),
          extra: {
            'currentUserId': widget.currentUserId,
            'otherUserId': otherUserId,
            'otherUserName': otherUserName,
            'otherUserPhotoUrl': otherUserPhotoUrl,
          },
        );
        break;
      case 'remove':
        _confirmRemove(context);
        break;
      case 'block':
        _confirmBlock(context, otherUserId);
        break;
    }
  }

  void _confirmRemove(BuildContext context) {
    // Capture BLoC reference before showing dialog
    final bloc = context.read<ConnectionBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Connection?'),
        content: const Text(
          'You will no longer be connected with this user. '
          'You can reconnect by sending a new request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(ConnectionRemove(widget.connection.id));
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _confirmBlock(BuildContext context, String otherUserId) {
    // Capture BLoC and theme reference before showing dialog
    final bloc = context.read<ConnectionBloc>();
    final errorColor = Theme.of(context).colorScheme.error;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block User?'),
        content: const Text(
          'This user will not be able to send you connection requests '
          'or see you in nearby users. You can unblock them later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(ConnectionBlockUser(otherUserId));
            },
            style: TextButton.styleFrom(
              foregroundColor: errorColor,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}

class _EmptyConnectionsState extends StatelessWidget {
  final VoidCallback onFindPeople;

  const _EmptyConnectionsState({required this.onFindPeople});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 24),
            Text(
              'No connections yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Find people nearby and connect with them\nto grow your network.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onFindPeople,
              icon: const Icon(Icons.radar),
              label: const Text('Find People Nearby'),
            ),
          ],
        ),
      ),
    );
  }
}
