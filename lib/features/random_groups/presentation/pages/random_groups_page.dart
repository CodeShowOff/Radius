import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/random_group.dart';
import '../bloc/random_group_bloc.dart';

/// Page displaying random groups for discovery.
///
/// Shows:
/// - Groups the user is a member of
/// - All active random groups for discovery
/// - Search/filter options
class RandomGroupsPage extends StatefulWidget {
  const RandomGroupsPage({super.key});

  @override
  State<RandomGroupsPage> createState() => _RandomGroupsPageState();
}

class _RandomGroupsPageState extends State<RandomGroupsPage> {
  bool _initialized = false;
  String? _selectedTopic;

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
      context.read<RandomGroupBloc>()
        ..add(const WatchActiveRandomGroups())
        ..add(WatchUserRandomGroups(authState.user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Random Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGroups,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<RandomGroupBloc, RandomGroupState>(
        builder: (context, state) {
          if (state.status == RandomGroupBlocStatus.loading &&
              state.activeGroups.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == RandomGroupBlocStatus.error) {
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
                // My Groups Section
                if (state.userGroups.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'My Groups',
                      subtitle: 'Groups you\'re a member of',
                      icon: Icons.group,
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final group = state.userGroups[index];
                        return _RandomGroupCard(
                          group: group,
                          isMember: true,
                        );
                      },
                      childCount: state.userGroups.length,
                    ),
                  ),
                ],

                // Discover Section
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: 'Discover Groups',
                    subtitle: 'Find new communities to join',
                    icon: Icons.explore,
                  ),
                ),

                // Topic Filter
                SliverToBoxAdapter(
                  child: _TopicFilter(
                    selectedTopic: _selectedTopic,
                    onTopicChanged: (topic) {
                      setState(() => _selectedTopic = topic);
                    },
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
                        // Filter by topic if selected
                        if (_selectedTopic != null &&
                            group.topic != _selectedTopic) {
                          return const SizedBox.shrink();
                        }
                        // Skip groups user is already in
                        final isMember =
                            state.userGroups.any((g) => g.id == group.id);
                        return _RandomGroupCard(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.createRandomGroup),
        icon: const Icon(Icons.add),
        label: const Text('Create Group'),
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
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
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

class _TopicFilter extends StatelessWidget {
  final String? selectedTopic;
  final ValueChanged<String?> onTopicChanged;

  const _TopicFilter({
    required this.selectedTopic,
    required this.onTopicChanged,
  });

  static const _topics = [
    'General',
    'Gaming',
    'Music',
    'Sports',
    'Tech',
    'Movies',
    'Books',
    'Food',
    'Travel',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _topics.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                label: const Text('All'),
                selected: selectedTopic == null,
                onSelected: (_) => onTopicChanged(null),
              ),
            );
          }
          final topic = _topics[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(topic),
              selected: selectedTopic == topic,
              onSelected: (_) => onTopicChanged(topic),
            ),
          );
        },
      ),
    );
  }
}

class _RandomGroupCard extends StatelessWidget {
  final RandomGroup group;
  final bool isMember;

  const _RandomGroupCard({
    required this.group,
    required this.isMember,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => context.push(Routes.randomGroupDetailWith(group.id)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Group avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Group info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMember)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Joined',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (group.topic != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.topic!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    if (group.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${group.memberCount} members',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (group.lastMessagePreview != null) ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              group.lastMessagePreview!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No groups found',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to create a group!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
