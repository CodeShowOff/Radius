import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/join_request.dart';
import '../../domain/entities/random_group.dart';
import '../../domain/entities/random_group_member.dart';
import '../bloc/random_group_bloc.dart';

/// Page showing details of a random group.
///
/// Displays:
/// - Group info (name, topic, description)
/// - Join status/button
/// - Member list (for members)
/// - Pending requests (for admins)
/// - Admin controls
class RandomGroupDetailPage extends StatefulWidget {
  final String groupId;

  const RandomGroupDetailPage({
    super.key,
    required this.groupId,
  });

  @override
  State<RandomGroupDetailPage> createState() => _RandomGroupDetailPageState();
}

class _RandomGroupDetailPageState extends State<RandomGroupDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadGroupDetails();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadGroupDetails() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final bloc = context.read<RandomGroupBloc>();
      bloc.add(LoadRandomGroupDetails(widget.groupId));
      bloc.add(WatchRandomGroupMembers(widget.groupId));
      bloc.add(CheckMembershipStatus(
        groupId: widget.groupId,
        userId: authState.user.id,
      ));
      // Watch pending requests for all users (admins will see them in UI)
      bloc.add(WatchPendingRequests(widget.groupId));
    }
  }

  String? _getCurrentUserId() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      return authState.user.id;
    }
    return null;
  }

  void _requestToJoin() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final user = authState.user;
    context.read<RandomGroupBloc>().add(RequestToJoinRandomGroup(
          groupId: widget.groupId,
          requesterId: user.id,
          requesterUsername: user.username,
          requesterDisplayName: user.displayName,
          requesterPhotoUrl: user.avatarUrl,
        ));
  }

  void _openChat() {
    context.push(Routes.randomGroupChatWith(widget.groupId));
  }

  void _leaveGroup() {
    final userId = _getCurrentUserId();
    if (userId == null) return;
    
    // Get username for system message
    final authState = context.read<AuthBloc>().state;
    final username = authState is AuthAuthenticated 
        ? (authState.user.displayName ?? authState.user.username)
        : null;
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<RandomGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              bloc.add(LeaveRandomGroup(
                    groupId: widget.groupId,
                    userId: userId,
                    username: username,
                  ));
              context.pop();
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup() {
    final userId = _getCurrentUserId();
    if (userId == null) return;
    
    // Capture the bloc before showing dialog to ensure it's accessible
    final bloc = context.read<RandomGroupBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text(
          'Are you sure you want to delete this group? This action cannot be undone.',
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
              bloc.add(DeleteRandomGroup(
                    groupId: widget.groupId,
                    userId: userId,
                  ));
              context.pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = _getCurrentUserId();

    return BlocConsumer<RandomGroupBloc, RandomGroupState>(
      listener: (context, state) {
        if (state.status == RandomGroupBlocStatus.joined) {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Request Sent'),
              content: const Text(
                'Your join request has been sent to the group admin. You will be notified once your request is approved.',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else if (state.status == RandomGroupBlocStatus.error &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final group = state.selectedGroup;
        final isAdmin = state.membershipStatus == UserMembershipStatus.admin ||
            state.membershipStatus == UserMembershipStatus.creator;
        final isMember = state.membershipStatus == UserMembershipStatus.member ||
            isAdmin;
        final isPending = state.membershipStatus == UserMembershipStatus.pending;

        if (group == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              group.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              // Settings button (admin only) with badge showing pending requests
              if (isAdmin)
                IconButton(
                  icon: state.pendingRequests.isNotEmpty
                      ? Badge(
                          label: Text('${state.pendingRequests.length}'),
                          backgroundColor: theme.colorScheme.error,
                          child: const Icon(Icons.settings),
                        )
                      : const Icon(Icons.settings),
                  onPressed: () {
                    context.push(Routes.randomGroupSettingsWith(widget.groupId));
                  },
                  tooltip: state.pendingRequests.isNotEmpty
                      ? 'Group Settings (${state.pendingRequests.length} pending requests)'
                      : 'Group Settings',
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'leave':
                      _leaveGroup();
                      break;
                    case 'delete':
                      _deleteGroup();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (isMember &&
                      state.membershipStatus != UserMembershipStatus.creator)
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(Icons.exit_to_app),
                          SizedBox(width: 8),
                          Text('Leave Group'),
                        ],
                      ),
                    ),
                  if (state.membershipStatus == UserMembershipStatus.creator)
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Text(
                            'Delete Group',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            bottom: isMember
                ? TabBar(
                    controller: _tabController,
                    tabs: [
                      const Tab(text: 'About'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Members'),
                            if (isAdmin && state.pendingRequests.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Badge(
                                label: Text('${state.pendingRequests.length}'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          body: isMember
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _AboutTab(group: group),
                    _MembersTab(
                      groupId: widget.groupId,
                      members: state.selectedGroupMembers,
                      pendingRequests: state.pendingRequests,
                      isAdmin: isAdmin,
                      currentUserId: userId,
                    ),
                  ],
                )
              : _NonMemberView(
                  group: group,
                  isPending: isPending,
                  onRequestToJoin: _requestToJoin,
                  isJoining: state.status == RandomGroupBlocStatus.joining,
                ),
          bottomNavigationBar: isMember
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.chat),
                      label: const Text('Open Chat'),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

class _AboutTab extends StatelessWidget {
  final RandomGroup group;

  const _AboutTab({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Center(
            child: Column(
              children: [
                CachedAvatar(
                  imageUrl: group.photoUrl,
                  name: group.name,
                  radius: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  group.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (group.topic != null) ...[
                  const SizedBox(height: 4),
                  Chip(
                    label: Text(group.topic!),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                icon: Icons.people,
                value: '${group.memberCount}',
                label: 'Members',
              ),
              _StatItem(
                icon: Icons.calendar_today,
                value: _formatDate(group.createdAt),
                label: 'Created',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          if (group.description != null && group.description!.isNotEmpty) ...[
            Text(
              'About',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.description!,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
          ],

          // Creator info
          Text(
            'Created by',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CachedAvatar(
              imageUrl: group.creatorPhotoUrl,
              name: group.creatorDisplayName ?? group.creatorUsername,
              radius: 20,
            ),
            title: Text(group.creatorDisplayName ?? group.creatorUsername),
            subtitle: Text('@${group.creatorUsername}'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MembersTab extends StatelessWidget {
  final String groupId;
  final List<RandomGroupMember> members;
  final List<JoinRequest> pendingRequests;
  final bool isAdmin;
  final String? currentUserId;

  const _MembersTab({
    required this.groupId,
    required this.members,
    required this.pendingRequests,
    required this.isAdmin,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pending requests section (admin only)
        if (isAdmin && pendingRequests.isNotEmpty) ...[
          Card(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person_add,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pending Requests (${pendingRequests.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...pendingRequests.map((request) => _PendingRequestTile(
                        request: request,
                        groupId: groupId,
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Members section
        Text(
          'Members (${members.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...members.map((member) => _MemberTile(
              member: member,
              groupId: groupId,
              isAdmin: isAdmin,
              isCurrentUser: member.id == currentUserId,
            )),
      ],
    );
  }
}

class _PendingRequestTile extends StatelessWidget {
  final JoinRequest request;
  final String groupId;

  const _PendingRequestTile({
    required this.request,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.read<AuthBloc>().state;
    final adminId = authState is AuthAuthenticated ? authState.user.id : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CachedAvatar(
              imageUrl: request.requesterPhotoUrl,
              name: request.requesterDisplayName ?? request.requesterUsername,
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.requesterDisplayName ?? request.requesterUsername,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '@${request.requesterUsername}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: theme.colorScheme.error,
              onPressed: () {
                context.read<RandomGroupBloc>().add(RejectJoinRequest(
                      groupId: groupId,
                      requestId: request.id,
                      adminId: adminId,
                    ));
              },
              tooltip: 'Reject',
            ),
            IconButton(
              icon: const Icon(Icons.check),
              color: theme.colorScheme.primary,
              onPressed: () {
                context.read<RandomGroupBloc>().add(ApproveJoinRequest(
                      groupId: groupId,
                      requestId: request.id,
                      adminId: adminId,
                      requesterUsername: request.requesterDisplayName ?? request.requesterUsername,
                    ));
              },
              tooltip: 'Approve',
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final RandomGroupMember member;
  final String groupId;
  final bool isAdmin;
  final bool isCurrentUser;

  const _MemberTile({
    required this.member,
    required this.groupId,
    required this.isAdmin,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      leading: CachedAvatar(
        imageUrl: member.photoUrl,
        name: member.displayName ?? member.username,
        radius: 20,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.displayName ?? member.username,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (member.isAdmin) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Admin',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Text(
              '(You)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text('@${member.username}'),
      trailing: isAdmin && !isCurrentUser && !member.isAdmin
          ? PopupMenuButton<String>(
              onSelected: (value) {
                final authState = context.read<AuthBloc>().state;
                final adminId =
                    authState is AuthAuthenticated ? authState.user.id : '';

                switch (value) {
                  case 'promote':
                    context.read<RandomGroupBloc>().add(PromoteToAdmin(
                          groupId: groupId,
                          memberId: member.id,
                          adminId: adminId,
                        ));
                    break;
                  case 'remove':
                    context.read<RandomGroupBloc>().add(RemoveRandomGroupMember(
                          groupId: groupId,
                          memberId: member.id,
                          adminId: adminId,
                          memberUsername: member.displayName ?? member.username,
                        ));
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'promote',
                  child: Row(
                    children: [
                      Icon(Icons.star),
                      SizedBox(width: 8),
                      Text('Make Admin'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.remove_circle,
                          color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Text('Remove',
                          style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _NonMemberView extends StatelessWidget {
  final RandomGroup group;
  final bool isPending;
  final VoidCallback onRequestToJoin;
  final bool isJoining;

  const _NonMemberView({
    required this.group,
    required this.isPending,
    required this.onRequestToJoin,
    required this.isJoining,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Group header
          Center(
            child: Column(
              children: [
                CachedAvatar(
                  imageUrl: group.photoUrl,
                  name: group.name,
                  radius: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  group.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (group.topic != null) ...[
                  const SizedBox(height: 4),
                  Chip(
                    label: Text(group.topic!),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                icon: Icons.people,
                value: '${group.memberCount}',
                label: 'Members',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          if (group.description != null && group.description!.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About this group',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      group.description!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Join button/status
          if (isPending)
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_top,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Request Pending',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Waiting for admin approval',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: isJoining ? null : onRequestToJoin,
                  icon: isJoining
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(isJoining ? 'Requesting...' : 'Request to Join'),
                ),
                const SizedBox(height: 8),
                Text(
                  'An admin will review your request',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
