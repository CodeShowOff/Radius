import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/nearby_group.dart';
import '../bloc/nearby_group_bloc.dart';

/// Page displaying user's joined nearby groups.
///
/// Shows:
/// - User's own active group (if any)
/// - Groups user is currently a member of (via Bluetooth)
/// Discovery has been moved to a separate page.
class NearbyGroupsPage extends StatefulWidget {
  const NearbyGroupsPage({super.key});

  @override
  State<NearbyGroupsPage> createState() => _NearbyGroupsPageState();
}

class _NearbyGroupsPageState extends State<NearbyGroupsPage> {
  bool _initialized = false;
  String? _lastUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final currentUserId = authState.user.id;
      
      // Check if user has changed (account switch)
      if (_lastUserId != null && _lastUserId != currentUserId) {
        // User changed - reset the BLoC to clean up old subscriptions
        context.read<NearbyGroupBloc>().add(const ResetNearbyGroupState());
        _initialized = false;
      }
      
      _lastUserId = currentUserId;
      
      if (!_initialized) {
        _initialized = true;
        _loadGroups();
      }
    }
  }

  void _loadGroups() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final bloc = context.read<NearbyGroupBloc>();
      bloc
        ..add(WatchUserNearbyGroups(authState.user.id))
        ..add(LoadUserActiveGroup(authState.user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Nearby Groups',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore),
            onPressed: () => context.push(Routes.discoverNearbyGroups),
            tooltip: 'Discover Groups',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGroups,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<NearbyGroupBloc, NearbyGroupState>(
        builder: (context, state) {
          if (state.status == NearbyGroupBlocStatus.loading &&
              state.userGroups.isEmpty &&
              state.myActiveGroup == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == NearbyGroupBlocStatus.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage ?? 'Something went wrong',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadGroups,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final hasGroups = state.myActiveGroup != null || state.userGroups.isNotEmpty;

          if (!hasGroups) {
            return _EmptyGroupsView(
              onDiscoverTap: () => context.push(Routes.discoverNearbyGroups),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadGroups(),
            child: CustomScrollView(
              slivers: [
                // My Active Group Section
                if (state.myActiveGroup != null) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'My Active Group',
                      icon: Icons.all_inclusive,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _MyActiveGroupCard(group: state.myActiveGroup!),
                  ),
                ],

                // Groups I'm In Section
                if (state.userGroups.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Groups I\'m In',
                      subtitle: 'Via Bluetooth discovery',
                      icon: Icons.group,
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final group = state.userGroups[index];
                        return _NearbyGroupCard(group: group);
                      },
                      childCount: state.userGroups.length,
                    ),
                  ),
                ],

                // Bottom padding
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: BlocBuilder<NearbyGroupBloc, NearbyGroupState>(
        buildWhen: (prev, curr) => prev.myActiveGroup != curr.myActiveGroup,
        builder: (context, state) {
          if (state.myActiveGroup != null) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton.extended(
            onPressed: () => context.push(Routes.createNearbyGroup),
            icon: const Icon(Icons.add),
            label: const Text('Create Group'),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyActiveGroupCard extends StatelessWidget {
  final NearbyGroup group;

  const _MyActiveGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push(Routes.nearbyGroupChatWith(group.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.all_inclusive,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Scanning • ${group.memberCount} nearby',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => _showCloseConfirmation(context),
                    tooltip: 'Close group',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          context.push(Routes.nearbyGroupChatWith(group.id)),
                      icon: const Icon(Icons.chat),
                      label: const Text('Open Chat'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCloseConfirmation(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<NearbyGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Group?'),
        content: const Text(
          'This will permanently delete the group, remove all members, '
          'and erase all chat messages. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(CloseNearbyGroup(
                    groupId: group.id,
                    userId: authState.user.id,
                  ));
            },
            child: const Text('Delete Group'),
          ),
        ],
      ),
    );
  }
}

class _NearbyGroupCard extends StatelessWidget {
  final NearbyGroup group;

  const _NearbyGroupCard({
    required this.group,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => context.push(Routes.nearbyGroupChatWith(group.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'by ${group.creatorDisplayName ?? 'Anonymous'} • ${group.memberCount} nearby',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (group.lastMessagePreview != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.lastMessagePreview!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'In Range',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGroupsView extends StatelessWidget {
  final VoidCallback onDiscoverTap;

  const _EmptyGroupsView({required this.onDiscoverTap});

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
              Icons.groups_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Groups Yet',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'You haven\'t joined any nearby groups yet.\nDiscover groups around you or create your own.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onDiscoverTap,
              icon: const Icon(Icons.explore),
              label: const Text('Discover Groups'),
            ),
          ],
        ),
      ),
    );
  }
}
