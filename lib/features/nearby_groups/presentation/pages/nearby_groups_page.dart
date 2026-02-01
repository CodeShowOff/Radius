import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/nearby_group.dart';
import '../bloc/nearby_group_bloc.dart';

/// Page displaying nearby groups for discovery and management.
///
/// Shows:
/// - User's own active group (if any)
/// - Groups user is currently a member of (via Bluetooth)
/// - All active nearby groups for discovery
class NearbyGroupsPage extends StatefulWidget {
  const NearbyGroupsPage({super.key});

  @override
  State<NearbyGroupsPage> createState() => _NearbyGroupsPageState();
}

class _NearbyGroupsPageState extends State<NearbyGroupsPage> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadGroups();
    }
  }

  void _loadGroups() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<NearbyGroupBloc>()
        ..add(const WatchActiveNearbyGroups())
        ..add(WatchUserNearbyGroups(authState.user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Groups'),
        actions: [
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
              state.activeGroups.isEmpty) {
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

          return RefreshIndicator(
            onRefresh: () async => _loadGroups(),
            child: CustomScrollView(
              slivers: [
                // My Active Group Section
                if (state.myActiveGroup != null) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'My Active Group',
                      icon: Icons.bluetooth_searching,
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
                        return _NearbyGroupCard(
                          group: group,
                          isMember: true,
                        );
                      },
                      childCount: state.userGroups.length,
                    ),
                  ),
                ],

                // Discover Nearby Groups Section
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: 'Discover Nearby',
                    subtitle: 'Active groups around you',
                    icon: Icons.explore,
                  ),
                ),

                if (state.activeGroups.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyDiscoverCard(),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final group = state.activeGroups[index];
                        // Skip groups user owns or is already in
                        if (group.id == state.myActiveGroup?.id) {
                          return const SizedBox.shrink();
                        }
                        final isMember = state.userGroups.any((g) => g.id == group.id);
                        return _NearbyGroupCard(
                          group: group,
                          isMember: isMember,
                        );
                      },
                      childCount: state.activeGroups.length,
                    ),
                  ),

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
                      Icons.bluetooth_searching,
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Group?'),
        content: const Text(
          'This will end the group and remove all members. '
          'Chat history will be preserved but the group will no longer be active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<NearbyGroupBloc>().add(CloseNearbyGroup(
                    groupId: group.id,
                    userId: authState.user.id,
                  ));
            },
            child: const Text('Close Group'),
          ),
        ],
      ),
    );
  }
}

class _NearbyGroupCard extends StatelessWidget {
  final NearbyGroup group;
  final bool isMember;

  const _NearbyGroupCard({
    required this.group,
    required this.isMember,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: isMember
            ? () => context.push(Routes.nearbyGroupChatWith(group.id))
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CachedAvatar(
                imageUrl: group.creatorPhotoUrl,
                name: group.name,
                radius: 24,
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
              if (isMember)
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
                )
              else
                Icon(
                  Icons.bluetooth_disabled,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDiscoverCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.groups_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No active groups nearby',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a group to start chatting with people around you',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}
