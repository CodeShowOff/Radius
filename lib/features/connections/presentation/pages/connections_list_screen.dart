import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/connection.dart';
import '../bloc/connection_bloc.dart';

/// Screen displaying user's connections list.
class ConnectionsListScreen extends StatelessWidget {
  const ConnectionsListScreen({super.key});

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
                      // TODO: Navigate to requests screen
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
                // TODO: Navigate to nearby screen
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
                return _ConnectionTile(
                  connection: connection,
                  currentUserId: state.userId!,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final Connection connection;
  final String currentUserId;

  const _ConnectionTile({
    required this.connection,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final otherUserId = connection.getOtherUserId(currentUserId);

    // TODO: Load other user's profile data
    // For now we'll show placeholder
    const displayName = 'Connected User';
    const photoUrl = null;

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
      title: const Text(displayName),
      subtitle: Text(
        'Connected ${_formatDate(connection.connectedAt)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleMenuAction(context, value, otherUserId),
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
        // TODO: Navigate to user profile
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
      BuildContext context, String action, String otherUserId) {
    switch (action) {
      case 'message':
        // TODO: Navigate to chat
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
              context.read<ConnectionBloc>().add(
                    ConnectionRemove(connection.id),
                  );
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _confirmBlock(BuildContext context, String otherUserId) {
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
              context.read<ConnectionBloc>().add(
                    ConnectionBlockUser(otherUserId),
                  );
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
