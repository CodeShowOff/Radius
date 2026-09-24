import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';


import '../bloc/location_group_bloc.dart';
import '../widgets/group_card.dart';

/// Page displaying all location groups the user has joined.
class MyGroupsPage extends StatefulWidget {
  const MyGroupsPage({super.key});

  @override
  State<MyGroupsPage> createState() => _MyGroupsPageState();
}

class _MyGroupsPageState extends State<MyGroupsPage> {
  @override
  void initState() {
    super.initState();
    // Clear any stale flags from previous operations (e.g., failed deletions,
    // leave/delete where the listener was disposed before processing the flag)
    final groupState = context.read<LocationGroupBloc>().state;
    if (groupState.hasError) {
      context.read<LocationGroupBloc>().add(const ClearGroupError());
    }
    if (groupState.groupDeleted) {
      context.read<LocationGroupBloc>().add(const ClearGroupDeletionFlag());
    }
    if (groupState.groupLeft) {
      context.read<LocationGroupBloc>().add(const ClearGroupLeftFlag());
    }

    // Only load if not already loaded for this user
    // The BLoC will handle checking if data is already available
    // and will skip redundant loads while keeping real-time streams active
    final authState = context.read<AuthBloc>().state;

    if (authState is AuthAuthenticated) {
      // Only trigger load if status is initial or data is for a different user
      if (groupState.status == GroupBlocStatus.initial ||
          groupState.userGroupsUserId != authState.user.id) {
        _loadUserGroups();
      }
    }
  }

  void _loadUserGroups() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context
          .read<LocationGroupBloc>()
          .add(LoadUserGroups(userId: authState.user.id));
    }
  }

  Future<void> _forceRefreshGroups() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context
          .read<LocationGroupBloc>()
          .add(ForceRefreshUserGroups(userId: authState.user.id));
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }



  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Location Groups',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.locationGroups),
            icon: const Icon(Icons.explore),
            tooltip: 'Discover Groups',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _forceRefreshGroups,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _forceRefreshGroups,
        child: BlocBuilder<LocationGroupBloc, LocationGroupState>(
          builder: (context, state) {
            // Only show full-screen spinner for the truly initial state
            // (before RealTimeDataManager dispatches any event).
            // Once loading has started, show content area directly so
            // tab switches feel instant (WhatsApp pattern).
            if (state.status == GroupBlocStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.hasError) {
              return Center(
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
                      'Failed to load groups',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loadUserGroups,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (state.userGroups.isEmpty) {
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
                        'You haven\'t joined any location groups yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: () => context.push(Routes.locationGroups),
                        icon: const Icon(Icons.explore),
                        label: const Text('Discover Groups'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              itemCount: state.userGroups.length,
              itemBuilder: (context, index) {
                final group = state.userGroups[index];
                final unreadCount = state.userGroupUnreadCounts[group.id] ?? 0;


                return GroupCard(
                  group: group,
                  showChatPreview: true,
                  unreadCount: unreadCount,
                  onTap: () {
                    context.push(Routes.locationGroupChatWith(group.id));
                  },
                  onLongPress: null,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.createLocationGroup),
        child: const Icon(Icons.add),
      ),
    );
  }
}
