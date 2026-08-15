import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../chat/presentation/bloc/conversations_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../data/connection_service.dart';
import '../../domain/entities/connection.dart';
import '../bloc/connection_bloc.dart';
import '../bloc/suggested_connections_cubit.dart';
import '../bloc/suggested_connections_state.dart';

/// Connections page showing suggested connections and your network.
class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SuggestedConnectionsCubit(getIt<ConnectionService>()),
      child: const _ConnectionsView(),
    );
  }
}

class _ConnectionsView extends StatefulWidget {
  const _ConnectionsView();

  @override
  State<_ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends State<_ConnectionsView> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    
    final connectionState = context.read<ConnectionBloc>().state;
    final authState = context.read<AuthBloc>().state;
    
    if (authState is AuthAuthenticated) {
      final currentUserId = authState.user.id;
      
      // Load People You May Know
      context.read<SuggestedConnectionsCubit>().loadSuggestions(currentUserId);
      
      final blocUserId = connectionState.userId;
      if (blocUserId == null || blocUserId != currentUserId) {
        if (connectionState.status == ConnectionBlocStatus.initial) {
          _loadConnections();
        }
      }
    }
  }

  void _loadConnections() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final profileState = context.read<ProfileBloc>().state;
      String? displayName;
      String? photoUrl;
      if (profileState is ProfileLoaded) {
        displayName = profileState.profile.name;
        photoUrl = profileState.profile.photoUrl;
      }

      context.read<ConnectionBloc>().add(ConnectionLoadAll(
            authState.user.id,
            displayName: displayName,
            photoUrl: photoUrl,
          ));
    }
  }

  Future<void> _refreshConnections() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<SuggestedConnectionsCubit>().loadSuggestions(authState.user.id);
    }
    context.read<ConnectionBloc>().add(const ConnectionForceRefresh());
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.read<AuthBloc>().state;
    final currentUserId = (authState is AuthAuthenticated) ? authState.user.id : '';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshConnections,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // --- Sliver App Bar ---
            SliverAppBar(
              floating: true,
              pinned: true,
              elevation: 0,
              backgroundColor: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surface,
              title: _isSearching
                  ? Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'Search network...',
                          hintStyle: TextStyle(color: theme.colorScheme.outline),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    )
                  : const Text(
                      'Connections',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                    ),
              actions: [
                if (_isSearching)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                      });
                    },
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search Connections',
                    onPressed: () => setState(() => _isSearching = true),
                  ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Add Connection',
                  onPressed: () => context.push(Routes.discoverySearch),
                ),
                const SizedBox(width: 8),
              ],
            ),

            // --- Suggested Connections (People You May Know) ---
            if (!_isSearching && _searchQuery.isEmpty)
              SliverToBoxAdapter(
                child: _buildSuggestedConnections(theme, currentUserId),
              ),

            // --- Your Network Header ---
            if (!_isSearching && _searchQuery.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  child: Text(
                    'Your Network',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),

            // --- Connections List ---
            BlocBuilder<ConnectionBloc, ConnectionBlocState>(
              builder: (context, state) {
                if (state.status == ConnectionBlocStatus.initial ||
                    (state.status == ConnectionBlocStatus.loading && state.connections.isEmpty)) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (state.status == ConnectionBlocStatus.error) {
                  return SliverToBoxAdapter(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 40),
                          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                          const SizedBox(height: 16),
                          Text(state.errorMessage ?? 'Error', style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: _loadConnections,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state.connections.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'No connections yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Build your network by adding friends.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => context.push(Routes.discoverySearch),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Find People'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return _ConnectionsSliverList(
                  connections: state.connections,
                  currentUserId: state.userId ?? currentUserId,
                  searchQuery: _searchQuery,
                  onUserTap: (connection, profile) => _navigateToChat(context, connection, state.userId ?? currentUserId, profile),
                  onProfilePhotoTap: (connection, profile) => _showUserDetails(context, connection, state.userId ?? currentUserId, profile),
                );
              },
            ),
            
            // Bottom padding for scroll
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedConnections(ThemeData theme, String currentUserId) {
    return BlocBuilder<SuggestedConnectionsCubit, SuggestedConnectionsState>(
      builder: (context, state) {
        if (state is SuggestedConnectionsLoading || state is SuggestedConnectionsInitial) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is SuggestedConnectionsError) {
          return const SizedBox.shrink(); // Hide silently on error
        }

        if (state is SuggestedConnectionsLoaded) {
          if (state.suggestions.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'People You May Know',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.suggestions.length,
                  itemBuilder: (context, index) {
                    final user = state.suggestions[index];
                    return _SuggestedUserCard(
                      user: user,
                      currentUserId: currentUserId,
                    );
                  },
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _navigateToChat(
    BuildContext context,
    Connection connection,
    String currentUserId,
    Map<String, dynamic> profile,
  ) {
    final otherUserId = connection.getOtherUserId(currentUserId);
    final conversationId = Conversation.createConversationId(currentUserId, otherUserId);
    context.push(
      Routes.chatWith(conversationId),
      extra: {
        'currentUserId': currentUserId,
        'otherUserId': otherUserId,
        'otherUserName': profile['displayName'] ?? 'User',
        'otherUserPhotoUrl': profile['photoUrl'],
      },
    );
  }

  void _showUserDetails(
    BuildContext context,
    Connection connection,
    String currentUserId,
    Map<String, dynamic> profile,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserDetailsSheet(
        connection: connection,
        currentUserId: currentUserId,
        profile: profile,
      ),
    );
  }
}

class _SuggestedUserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final String currentUserId;

  const _SuggestedUserCard({required this.user, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = user['userId'] as String;
    final displayName = user['displayName'] as String? ?? 'User';
    final photoUrl = user['photoUrl'] as String?;
    final reason = user['reason'] as String? ?? 'Suggested for you';

    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          CachedAvatar(
            imageUrl: photoUrl,
            name: displayName,
            radius: 36,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              displayName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              reason,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              height: 32,
              child: FilledButton(
                onPressed: () {
                  // Dispatch connect event
                  context.read<ConnectionBloc>().add(ConnectionSendRequest(
                    receiverId: userId,
                    receiverDisplayName: displayName,
                    receiverPhotoUrl: photoUrl,
                    source: 'people_you_may_know',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Request sent to $displayName')),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Connect', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionsSliverList extends StatelessWidget {
  final List<Connection> connections;
  final String currentUserId;
  final String searchQuery;
  final void Function(Connection, Map<String, dynamic>) onUserTap;
  final void Function(Connection, Map<String, dynamic>) onProfilePhotoTap;

  const _ConnectionsSliverList({
    required this.connections,
    required this.currentUserId,
    required this.searchQuery,
    required this.onUserTap,
    required this.onProfilePhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConversationsBloc, ConversationsState>(
      builder: (context, conversationsState) {
        final conversationMap = <String, Conversation>{
          for (final conv in conversationsState.conversations) conv.id: conv,
        };

        return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
          builder: (context, connectionState) {
            final entries = <_SortedEntry>[];

            for (final connection in connections) {
              final otherUserId = connection.getOtherUserId(currentUserId);
              final cachedProfile = connectionState.getCachedProfile(otherUserId);
              final profile = cachedProfile?.toMap() ?? {'id': otherUserId, 'displayName': 'User'};
              final displayName = profile['displayName'] as String? ?? 'User';

              if (searchQuery.isNotEmpty) {
                final query = searchQuery.toLowerCase();
                if (!displayName.toLowerCase().contains(query)) continue;
              }

              final conversationId = Conversation.createConversationId(
                connection.userId1,
                connection.userId2,
              );

              final conversation = conversationMap[conversationId] ??
                  Conversation(
                    id: conversationId,
                    participantIds: [connection.userId1, connection.userId2],
                    participantInfo: const {},
                    createdAt: connection.connectedAt,
                    lastMessageAt: null,
                  );

              final sortTime = conversation.lastMessageAt ?? connection.connectedAt;
              entries.add(_SortedEntry(
                connection: connection,
                conversation: conversation,
                profile: profile,
                displayName: displayName,
                photoUrl: profile['photoUrl'] as String?,
                sortTime: sortTime,
              ));
            }

            entries.sort((a, b) => b.sortTime.compareTo(a.sortTime));

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final e = entries[index];
                  return _ModernConnectionTile(
                    entry: e,
                    currentUserId: currentUserId,
                    onTap: () => onUserTap(e.connection, e.profile),
                    onLongPress: () => onProfilePhotoTap(e.connection, e.profile),
                  );
                },
                childCount: entries.length,
              ),
            );
          },
        );
      },
    );
  }
}

class _SortedEntry {
  final Connection connection;
  final Conversation conversation;
  final Map<String, dynamic> profile;
  final String displayName;
  final String? photoUrl;
  final DateTime sortTime;

  const _SortedEntry({
    required this.connection,
    required this.conversation,
    required this.profile,
    required this.displayName,
    required this.photoUrl,
    required this.sortTime,
  });
}

class _ModernConnectionTile extends StatelessWidget {
  final _SortedEntry entry;
  final String currentUserId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ModernConnectionTile({
    required this.entry,
    required this.currentUserId,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bio = entry.profile['bio'] as String?;
    
    // Create a premium look
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                CachedAvatar(
                  imageUrl: entry.photoUrl,
                  name: entry.displayName,
                  radius: 28,
                ),
                // Mock online indicator (active/online dot)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366), // Green dot
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.colorScheme.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bio != null && bio.isNotEmpty 
                      ? bio 
                      : 'Connected since ${_formatTime(entry.connection.connectedAt)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Quick Action Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  onPressed: onTap,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      if (now.day != time.day) return 'Yesterday';
      return 'Today';
    } else if (difference.inDays < 7) {
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.month}/${time.day}/${time.year.toString().substring(2)}';
    }
  }
}

class _UserDetailsSheet extends StatelessWidget {
  final Connection connection;
  final String currentUserId;
  final Map<String, dynamic> profile;

  const _UserDetailsSheet({
    required this.connection,
    required this.currentUserId,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile['displayName'] as String? ?? 'User';
    final photoUrl = profile['photoUrl'] as String?;
    final bio = profile['bio'] as String?;
    final otherUserId = connection.getOtherUserId(currentUserId);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: CachedAvatar(
                        imageUrl: photoUrl,
                        name: displayName,
                        radius: 60,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        bio,
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 32),
                    _buildActionRow(context, theme, otherUserId, displayName),
                    const SizedBox(height: 32),
                    _buildDangerZone(context, theme, connection, otherUserId, displayName),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionRow(BuildContext context, ThemeData theme, String otherUserId, String displayName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionButton(
          icon: Icons.chat,
          label: 'Message',
          onTap: () {
            Navigator.pop(context);
            final conversationId = Conversation.createConversationId(currentUserId, otherUserId);
            context.push(Routes.chatWith(conversationId));
          },
        ),
      ],
    );
  }

  Widget _buildDangerZone(BuildContext context, ThemeData theme, Connection connection, String otherUserId, String displayName) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.person_remove, color: theme.colorScheme.error),
            title: Text('Remove Connection', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _showRemoveDialog(context, connection, displayName);
            },
          ),
          Divider(height: 1, color: theme.colorScheme.error.withValues(alpha: 0.1)),
          ListTile(
            leading: Icon(Icons.block, color: theme.colorScheme.error),
            title: Text('Block User', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _showBlockDialog(context, otherUserId, displayName);
            },
          ),
        ],
      ),
    );
  }

  void _showRemoveDialog(BuildContext context, Connection connection, String displayName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Connection'),
        content: Text('Are you sure you want to remove $displayName from your connections? You will no longer be able to message them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ConnectionBloc>().add(ConnectionRemove(connection.id));
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context, String blockedId, String displayName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Are you sure you want to block $displayName? They will no longer be able to find you or message you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ConnectionBloc>().add(ConnectionBlockUser(blockedId, blockedName: displayName));
            },
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
