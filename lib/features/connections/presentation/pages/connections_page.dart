import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/firebase/firestore_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../domain/entities/connection.dart';
import '../bloc/connection_bloc.dart';

/// WhatsApp-style connections page showing all connected users.
///
/// Features:
/// - List of all connected users with profile photos
/// - Tap on user to start/continue chat
/// - Tap on profile photo to see user details
/// - Search functionality
/// - Pending requests badge
class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  void _loadConnections() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      // Get profile info if available
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSearching ? _buildSearchAppBar() : _buildNormalAppBar(),
      body: BlocBuilder<ConnectionBloc, ConnectionBlocState>(
        builder: (context, state) {
          if (state.status == ConnectionBlocStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == ConnectionBlocStatus.error) {
            return _ErrorState(
              message: state.errorMessage ?? 'Failed to load connections',
              onRetry: _loadConnections,
            );
          }

          final connections = state.connections;

          if (connections.isEmpty) {
            return _EmptyState(
              onFindPeople: () => context.push(Routes.nearby),
            );
          }

          return _ConnectionsList(
            connections: connections,
            currentUserId: state.userId!,
            searchQuery: _searchQuery,
            onUserTap: (connection, profile) => _navigateToChat(
              context,
              connection,
              state.userId!,
              profile,
            ),
            onProfilePhotoTap: (connection, profile) => _showUserDetails(
              context,
              connection,
              state.userId!,
              profile,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.nearby),
        tooltip: 'Find people nearby',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: const Text('Connections'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _isSearching = true),
          tooltip: 'Search',
        ),
        _RequestsBadge(),
      ],
    );
  }

  AppBar _buildSearchAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          });
        },
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search connections...',
          border: InputBorder.none,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
      actions: [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
      ],
    );
  }

  void _navigateToChat(
    BuildContext context,
    Connection connection,
    String currentUserId,
    Map<String, dynamic> profile,
  ) {
    final otherUserId = connection.getOtherUserId(currentUserId);
    final conversationId =
        Conversation.createConversationId(currentUserId, otherUserId);

    context.push(
      Routes.chatWith(conversationId),
      extra: {
        'currentUserId': currentUserId,
        'otherUserId': otherUserId,
        'otherUserName': profile['displayName'] ?? 'User',
        'otherUserPhotoUrl': profile['avatarUrl'],
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

/// Badge showing pending connection requests count.
class _RequestsBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      buildWhen: (prev, curr) =>
          prev.receivedRequests.length != curr.receivedRequests.length,
      builder: (context, state) {
        final pendingCount = state.receivedRequests.length;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.mail_outline),
              onPressed: () => context.push(Routes.connectionRequests),
              tooltip: 'Requests',
            ),
            if (pendingCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    pendingCount > 99 ? '99+' : pendingCount.toString(),
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
    );
  }
}

/// List of connections with user profiles.
class _ConnectionsList extends StatelessWidget {
  final List<Connection> connections;
  final String currentUserId;
  final String searchQuery;
  final void Function(Connection, Map<String, dynamic>) onUserTap;
  final void Function(Connection, Map<String, dynamic>) onProfilePhotoTap;

  const _ConnectionsList({
    required this.connections,
    required this.currentUserId,
    required this.searchQuery,
    required this.onUserTap,
    required this.onProfilePhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: connections.length,
      itemBuilder: (context, index) {
        final connection = connections[index];
        final otherUserId = connection.getOtherUserId(currentUserId);

        return _ConnectionUserTile(
          connection: connection,
          userId: otherUserId,
          searchQuery: searchQuery,
          onTap: (profile) => onUserTap(connection, profile),
          onProfilePhotoTap: (profile) =>
              onProfilePhotoTap(connection, profile),
        );
      },
    );
  }
}

/// Individual connection tile that fetches user profile.
class _ConnectionUserTile extends StatefulWidget {
  final Connection connection;
  final String userId;
  final String searchQuery;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>) onProfilePhotoTap;

  const _ConnectionUserTile({
    required this.connection,
    required this.userId,
    required this.searchQuery,
    required this.onTap,
    required this.onProfilePhotoTap,
  });

  @override
  State<_ConnectionUserTile> createState() => _ConnectionUserTileState();
}

class _ConnectionUserTileState extends State<_ConnectionUserTile> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      // Public data lives under `/profiles/{userId}` (see firestore.rules).
      // Normalize to the legacy keys this UI expects.
      final doc = await getIt<FirestoreService>().getDocument(
        'profiles/${widget.userId}',
      );

      Map<String, dynamic> normalized;
      if (doc == null) {
        normalized = {'id': widget.userId, 'displayName': 'User'};
      } else {
        final displayName =
            (doc['name'] as String?)?.trim().isNotEmpty == true
                ? (doc['name'] as String).trim()
                : (doc['displayName'] as String?)?.trim().isNotEmpty == true
                    ? (doc['displayName'] as String).trim()
                    : 'User';

        final avatarUrl = (doc['photoUrl'] as String?)?.trim().isNotEmpty ==
                true
            ? (doc['photoUrl'] as String).trim()
            : (doc['avatarUrl'] as String?)?.trim().isNotEmpty == true
                ? (doc['avatarUrl'] as String).trim()
                : null;

        final bio = (doc['bio'] as String?)?.trim();

        normalized = {
          'id': widget.userId,
          'displayName': displayName,
          'avatarUrl': avatarUrl,
          'bio': bio,
        };
      }

      if (mounted) {
        setState(() {
          _profile = normalized;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _profile = {'id': widget.userId, 'displayName': 'User'};
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ListTile(
        leading: CircleAvatar(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Loading...'),
      );
    }

    final profile = _profile!;
    final displayName = profile['displayName'] as String? ?? 'User';
    final avatarUrl = profile['avatarUrl'] as String?;
    final bio = profile['bio'] as String?;

    // Filter by search query
    if (widget.searchQuery.isNotEmpty) {
      final query = widget.searchQuery.toLowerCase();
      if (!displayName.toLowerCase().contains(query)) {
        return const SizedBox.shrink();
      }
    }

    final theme = Theme.of(context);

    return ListTile(
      leading: GestureDetector(
        onTap: () => widget.onProfilePhotoTap(profile),
        child: Hero(
          tag: 'avatar_${widget.userId}',
          child: CircleAvatar(
            radius: 26,
            backgroundColor: theme.colorScheme.primaryContainer,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
        ),
      ),
      title: Text(
        displayName,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: bio != null && bio.isNotEmpty
          ? Text(
              bio,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          : Text(
              'Connected ${_formatTimeAgo(widget.connection.connectedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
      trailing: IconButton(
        icon: const Icon(Icons.message_outlined),
        onPressed: () => widget.onTap(profile),
        tooltip: 'Message',
      ),
      onTap: () => widget.onTap(profile),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (diff.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }
}

/// Bottom sheet showing user details.
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
    final avatarUrl = profile['avatarUrl'] as String?;
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
              // Handle bar
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
                    // Profile header
                    Center(
                      child: Hero(
                        tag: 'avatar_$otherUserId',
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage: avatarUrl != null
                              ? CachedNetworkImageProvider(avatarUrl)
                              : null,
                          child: avatarUrl == null
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 40,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Name
                    Center(
                      child: Text(
                        displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          bio,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Connection info card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.link,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Connection Info',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: 'Connected since',
                              value: _formatDate(connection.connectedAt),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              final conversationId =
                                  Conversation.createConversationId(
                                      currentUserId, otherUserId);
                              context.push(
                                Routes.chatWith(conversationId),
                                extra: {
                                  'currentUserId': currentUserId,
                                  'otherUserId': otherUserId,
                                  'otherUserName': displayName,
                                  'otherUserPhotoUrl': avatarUrl,
                                },
                              );
                            },
                            icon: const Icon(Icons.message),
                            label: const Text('Message'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Danger zone
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _confirmRemove(context),
                            icon: const Icon(Icons.person_remove),
                            label: const Text('Remove'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _confirmBlock(context, otherUserId),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                            icon: const Icon(Icons.block),
                            label: const Text('Block'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
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
              Navigator.pop(context);
              bloc.add(ConnectionRemove(connection.id));
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
              Navigator.pop(context);
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

/// Info row for details sheet.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state when no connections.
class _EmptyState extends StatelessWidget {
  final VoidCallback onFindPeople;

  const _EmptyState({required this.onFindPeople});

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
              'Find people nearby and connect with them\nto start messaging.',
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

/// Error state.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

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
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
