import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../chat/presentation/bloc/conversations_bloc.dart';
import '../../../chat/presentation/widgets/conversation_tile.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
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
    // The RealTimeDataManager initializes streams when the user authenticates.
    // We only need to trigger a load if:
    // 1. The bloc is in initial state (very first load), OR
    // 2. The bloc has no userId set (not yet initialized)
    // 
    // This prevents redundant loads when:
    // - Navigating between tabs (state already loaded)
    // - Navigating back to this page (state persisted in singleton bloc)
    // - RealTimeDataManager already triggered the load (status may be loading/loaded)
    final connectionState = context.read<ConnectionBloc>().state;
    final authState = context.read<AuthBloc>().state;
    
    // Only load if we have an authenticated user and the bloc isn't already
    // initialized for this user
    if (authState is AuthAuthenticated) {
      final currentUserId = authState.user.id;
      final blocUserId = connectionState.userId;
      
      // If bloc hasn't been initialized at all, OR if it's for a different user
      if (blocUserId == null || blocUserId != currentUserId) {
        // Bloc not initialized for this user - RealTimeDataManager should handle this,
        // but as a safety net we trigger the load
        if (connectionState.status == ConnectionBlocStatus.initial) {
          _loadConnections();
        }
      }
      // If blocUserId == currentUserId, the data is already loading/loaded
      // No need to do anything - streams are already active
    }
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

  // Refresh method for pull-to-refresh
  Future<void> _refreshConnections() async {
    _loadConnections();
    // Wait for the streams to emit at least once
    await Future.delayed(const Duration(milliseconds: 500));
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
          // Only show loading indicator on initial load
          if (state.status == ConnectionBlocStatus.initial ||
              (state.status == ConnectionBlocStatus.loading && 
               state.connections.isEmpty)) {
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
            return RefreshIndicator(
              onRefresh: _refreshConnections,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - 200,
                  child: _EmptyState(
                    onFindPeople: () => context.push(Routes.nearby),
                  ),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshConnections,
            child: _ConnectionsList(
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
      title: const Text(
        'Connections',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
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
      title: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Search connections...',
            hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            prefixIcon: Icon(
              Icons.search,
              color: Theme.of(context).colorScheme.outline,
              size: 20,
            ),
          ),
          onChanged: (value) => setState(() => _searchQuery = value),
        ),
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

/// Badge showing pending connection requests count from nearby.
class _RequestsBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      buildWhen: (prev, curr) {
        // Rebuild when the count of nearby requests changes
        final prevNearbyCount = prev.receivedRequests
            .where((req) => req.source == 'nearby')
            .length;
        final currNearbyCount = curr.receivedRequests
            .where((req) => req.source == 'nearby')
            .length;
        return prevNearbyCount != currNearbyCount;
      },
      builder: (context, state) {
        // Count only connection requests received from nearby
        final nearbyRequestsCount = state.receivedRequests
            .where((req) => req.source == 'nearby')
            .length;

        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.mail_outline),
              onPressed: () => context.push(Routes.connectionRequests),
              tooltip: 'Requests',
            ),
            if (nearbyRequestsCount > 0)
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
                    nearbyRequestsCount > 99 ? '99+' : nearbyRequestsCount.toString(),
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
/// Sorted by last message time (most recent first), just like home page.
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
    return BlocBuilder<ConversationsBloc, ConversationsState>(
      builder: (context, conversationsState) {
        // Sort connections by last message time (most recent first)
        final sortedConnections = List<Connection>.from(connections);
        sortedConnections.sort((a, b) {
          final conversationIdA = Conversation.createConversationId(a.userId1, a.userId2);
          final conversationIdB = Conversation.createConversationId(b.userId1, b.userId2);
          
          final conversationA = conversationsState.conversations.firstWhere(
            (conv) => conv.id == conversationIdA,
            orElse: () => Conversation(
              id: conversationIdA,
              participantIds: [a.userId1, a.userId2],
              participantInfo: const {},
              createdAt: a.connectedAt,
              lastMessageAt: null,
            ),
          );
          
          final conversationB = conversationsState.conversations.firstWhere(
            (conv) => conv.id == conversationIdB,
            orElse: () => Conversation(
              id: conversationIdB,
              participantIds: [b.userId1, b.userId2],
              participantInfo: const {},
              createdAt: b.connectedAt,
              lastMessageAt: null,
            ),
          );
          
          // Sort by last message time, most recent first
          // If no messages, use connection time
          final timeA = conversationA.lastMessageAt ?? a.connectedAt;
          final timeB = conversationB.lastMessageAt ?? b.connectedAt;
          return timeB.compareTo(timeA); // Descending order (newest first)
        });

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          itemCount: sortedConnections.length,
          itemBuilder: (context, index) {
            final connection = sortedConnections[index];
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
      },
    );
  }
}

/// Individual connection tile that uses cached profile from bloc.
/// 
/// This widget uses the profile cache in ConnectionBloc instead of
/// fetching profiles individually, eliminating loading spinners on tab switches.
/// Uses ConversationTile to match the home page display style and logic.
class _ConnectionUserTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BlocSelector<ConnectionBloc, ConnectionBlocState, CachedProfile?>(
      selector: (state) => state.getCachedProfile(userId),
      builder: (context, cachedProfile) {
        // Use cached profile or show minimal loading state
        final profile = cachedProfile?.toMap() ?? 
            {'id': userId, 'displayName': 'User'};
        
        final displayName = profile['displayName'] as String? ?? 'User';
        final photoUrl = profile['photoUrl'] as String?;

        // Filter by search query
        if (searchQuery.isNotEmpty) {
          final query = searchQuery.toLowerCase();
          if (!displayName.toLowerCase().contains(query)) {
            return const SizedBox.shrink();
          }
        }

        final conversationId = Conversation.createConversationId(
          connection.userId1,
          connection.userId2,
        );

        return BlocBuilder<ConversationsBloc, ConversationsState>(
          builder: (context, conversationsState) {
            // Find the conversation for this connection
            final conversation = conversationsState.conversations.firstWhere(
              (conv) => conv.id == conversationId,
              orElse: () => Conversation(
                id: conversationId,
                participantIds: [connection.userId1, connection.userId2],
                participantInfo: const {},
                createdAt: connection.connectedAt,
                lastMessageAt: null,
              ),
            );

            // Get current user ID for the ConversationTile
            final authState = context.read<AuthBloc>().state;
            final currentUserId = authState is AuthAuthenticated ? authState.user.id : '';

            // Use ConversationTile which has all the perfect logic from home page
            return ConversationTile(
              conversation: conversation,
              currentUserId: currentUserId,
              overrideDisplayName: displayName,
              overridePhotoUrl: photoUrl,
              onTap: () => onTap(profile),
            );
          },
        );
      },
    );
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
                        child: CachedAvatar(
                          imageUrl: photoUrl,
                          name: displayName,
                          radius: 60,
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
                                  'otherUserPhotoUrl': photoUrl,
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
