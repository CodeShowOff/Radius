import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/random_group.dart';
import '../bloc/random_group_bloc.dart';
import '../bloc/random_group_chat_bloc.dart';

/// Page for discovering random groups to join.
///
/// Shows all active random groups for discovery.
/// Users can filter by topic and request to join groups.
class DiscoverRandomGroupsPage extends StatefulWidget {
  const DiscoverRandomGroupsPage({super.key});

  @override
  State<DiscoverRandomGroupsPage> createState() =>
      _DiscoverRandomGroupsPageState();
}

class _DiscoverRandomGroupsPageState extends State<DiscoverRandomGroupsPage> {
  bool _initialized = false;
  String? _lastUserId;
  String? _selectedTopic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final currentUserId = authState.user.id;
      
      // Check if user has changed (account switch)
      if (_lastUserId != null && _lastUserId != currentUserId) {
        // User changed - reset the BLoC to clean up old subscriptions
        context.read<RandomGroupBloc>().add(const ResetRandomGroupState());
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
      // These are now idempotent - they skip if already watching same user
      context.read<RandomGroupBloc>()
        ..add(const WatchActiveRandomGroups())
        ..add(WatchUserRandomGroups(authState.user.id));
    }
  }

  void _refreshGroups() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      // Force refresh cancels existing subscriptions and re-subscribes
      context.read<RandomGroupBloc>().add(
        ForceRefreshRandomGroups(userId: authState.user.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Discover Groups',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshGroups,
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
            onRefresh: () async => _refreshGroups(),
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find Communities',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Browse groups by topic and request to join',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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
                  Builder(
                    builder: (context) {
                      // Filter groups by topic first for efficiency
                      final filteredGroups = _selectedTopic == null
                          ? state.activeGroups
                          : state.activeGroups
                              .where((g) => g.topic == _selectedTopic)
                              .toList();

                      if (filteredGroups.isEmpty) {
                        return SliverToBoxAdapter(
                          child: _EmptyDiscoverCard(),
                        );
                      }

                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final group = filteredGroups[index];
                            // Check if user is already in this group
                            final isMember =
                                state.userGroups.any((g) => g.id == group.id);
                            return _RandomGroupCard(
                              group: group,
                              isMember: isMember,
                              onTap: () {
                                if (isMember) {
                                  // Members go directly to chat
                                  context
                                      .push(Routes.randomGroupChatWith(group.id));
                                } else {
                                  // Non-members go to detail page to request join
                                  context
                                      .push(Routes.randomGroupDetailWith(group.id));
                                }
                              },
                              onLongPress: isMember && userId != null
                                  ? () {
                                      // Preload chat messages on long-press
                                      getIt<RandomGroupChatBloc>().add(
                                        PreloadRandomGroupChat(
                                          groupId: group.id,
                                          userId: userId,
                                        ),
                                      );
                                    }
                                  : null,
                            );
                          },
                          childCount: filteredGroups.length,
                        ),
                      );
                    },
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

class _TopicFilter extends StatelessWidget {
  final String? selectedTopic;
  final ValueChanged<String?> onTopicChanged;

  const _TopicFilter({
    required this.selectedTopic,
    required this.onTopicChanged,
  });

  static const _topics = [
    'Technology',
    'Gaming',
    'Music',
    'Sports',
    'Movies',
    'Books',
    'Art',
    'Food',
    'Travel',
    'Fitness',
    'Science',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selectedTopic == null,
            onSelected: (_) => onTopicChanged(null),
          ),
          ..._topics.map(
            (topic) => FilterChip(
              label: Text(topic),
              selected: selectedTopic == topic,
              onSelected: (_) => onTopicChanged(topic),
            ),
          ),
        ],
      ),
    );
  }
}

class _RandomGroupCard extends StatelessWidget {
  final RandomGroup group;
  final bool isMember;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _RandomGroupCard({
    required this.group,
    required this.isMember,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Group avatar
              CachedAvatar(
                imageUrl: group.photoUrl,
                name: group.name,
                radius: 28,
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
                isMember ? Icons.chat : Icons.chevron_right,
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
              'Try a different topic or create a new group',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
