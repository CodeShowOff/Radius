import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/random_group_chat_cache_service.dart';
import '../../data/random_group_chat_service.dart';
import '../../domain/entities/random_group.dart';
import '../bloc/random_group_bloc.dart';

/// Page displaying user's joined random groups.
///
/// Shows only groups the user is a member of.
/// Discovery has been moved to a separate page.
class RandomGroupsPage extends StatefulWidget {
  const RandomGroupsPage({super.key});

  @override
  State<RandomGroupsPage> createState() => _RandomGroupsPageState();
}

class _RandomGroupsPageState extends State<RandomGroupsPage> {
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      if (!_initialized) {
        _initialized = true;
        _loadGroups();
      }
    }
  }

  void _loadGroups() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      // Use WatchUserRandomGroups which is now idempotent -
      // it will skip if already watching the same user.
      context.read<RandomGroupBloc>().add(WatchUserRandomGroups(authState.user.id));
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

  /// Preload random group chat messages into cache directly via cache+chat services.
  Future<void> _preloadRandomGroupChat(String groupId, String userId) async {
    final cacheService = getIt<RandomGroupChatCacheService>();
    final chatService = getIt<RandomGroupChatService>();
    final logger = Logger();

    if (cacheService.hasValidCache(groupId, ttl: RandomGroupChatCacheService.defaultTtl)) {
      return;
    }

    try {
      final canRead = await chatService.isActiveMember(groupId: groupId, userId: userId);
      if (!canRead) return;

      final messages = await chatService.getMessages(groupId: groupId, limit: 50);
      if (messages.isNotEmpty) {
        cacheService.updateCache(
          groupId: groupId,
          messages: messages,
          hasMore: messages.length >= 50,
          isPreload: true,
        );
        logger.d('Preloaded ${messages.length} messages for random group $groupId');
      }
    } catch (e) {
      logger.d('Preload failed for random group $groupId: $e');
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
          'My Random Groups',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore),
            onPressed: () => context.push(Routes.discoverRandomGroups),
            tooltip: 'Discover Groups',
          ),
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
              state.userGroups.isEmpty) {
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

          if (state.userGroups.isEmpty) {
            return _EmptyGroupsView(
              onDiscoverTap: () => context.push(Routes.discoverRandomGroups),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refreshGroups(),
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: state.userGroups.length,
              itemBuilder: (context, index) {
                final group = state.userGroups[index];
                final unreadCount = state.userGroupUnreadCounts[group.id] ?? 0;
                return _RandomGroupCard(
                  group: group,
                  unreadCount: unreadCount,
                  onTap: () {
                    context.push(Routes.randomGroupChatWith(group.id));
                  },
                  onLongPress: userId != null
                      ? () {
                          _preloadRandomGroupChat(group.id, userId);
                        }
                      : null,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.createRandomGroup),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _RandomGroupCard extends StatelessWidget {
  final RandomGroup group;
  final int unreadCount;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _RandomGroupCard({
    required this.group,
    this.unreadCount = 0,
    this.onTap,
    this.onLongPress,
  });

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      // Today - show time
      final hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else {
      // Older - show date
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastActivity = group.lastMessageAt ?? group.lastActiveAt;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
          children: [
            // Group avatar - WhatsApp style
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: group.photoUrl != null
                  ? NetworkImage(group.photoUrl!)
                  : null,
              child: group.photoUrl == null
                  ? Text(
                      group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            
            // Group info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group name
                  Text(
                    group.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  
                  // Topic
                  Text(
                    group.topic ?? 'No topic',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  
                  // Last message or member info
                  Text(
                    group.lastMessagePreview ?? '${group.memberCount} members',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Right side - timestamp and unread count
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Timestamp
                Text(
                  _formatTimestamp(lastActivity),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: unreadCount > 0
                        ? const Color(0xFF25D366) // WhatsApp green
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                
                // Unread count badge
                if (unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366), // WhatsApp green
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 20),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
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
              'You haven\'t joined any random groups yet.\nDiscover groups to connect with people worldwide.',
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
