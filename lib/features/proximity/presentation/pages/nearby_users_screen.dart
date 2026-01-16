import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/ble_device.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../domain/entities/nearby_user.dart';
import '../bloc/nearby_users_bloc.dart';
import '../widgets/nearby_user_card.dart';
import '../widgets/nearby_users_empty_state.dart';
import '../widgets/nearby_users_filter_bar.dart';

/// Screen displaying nearby users discovered via BLE.
class NearbyUsersScreen extends StatefulWidget {
  const NearbyUsersScreen({super.key});

  @override
  State<NearbyUsersScreen> createState() => _NearbyUsersScreenState();
}

class _NearbyUsersScreenState extends State<NearbyUsersScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDiscovery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bloc = context.read<NearbyUsersBloc>();

    if (state == AppLifecycleState.paused) {
      // Stop discovery when app goes to background
      bloc.add(const NearbyUsersStopDiscovery());
    } else if (state == AppLifecycleState.resumed) {
      // Resume discovery when app comes to foreground
      _startDiscovery();
    }
  }

  void _startDiscovery() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<NearbyUsersBloc>().add(
            NearbyUsersStartDiscovery(authState.user.id),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
        actions: [
          // Scanning indicator
          BlocBuilder<NearbyUsersBloc, NearbyUsersState>(
            buildWhen: (prev, curr) => prev.isDiscovering != curr.isDiscovering,
            builder: (context, state) {
              if (state.isDiscovering) {
                return const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context
                    .read<NearbyUsersBloc>()
                    .add(const NearbyUsersRefresh()),
                tooltip: 'Refresh',
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<NearbyUsersBloc, NearbyUsersState>(
        listenWhen: (prev, curr) => curr.status == NearbyUsersStatus.error,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                action: SnackBarAction(
                  label: 'Settings',
                  onPressed: () async {
                    // Open app settings for permissions
                    await openAppSettings();
                  },
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              // Filter bar
              if (state.users.isNotEmpty)
                NearbyUsersFilterBar(
                  selectedFilter: state.filter,
                  allCount: state.users.length,
                  closeCount: state.users
                      .where((u) => u.proximity == BleProximity.immediate)
                      .length,
                  nearbyCount: state.users
                      .where((u) =>
                          u.proximity == BleProximity.immediate ||
                          u.proximity == BleProximity.near)
                      .length,
                  onFilterChanged: (filter) => context
                      .read<NearbyUsersBloc>()
                      .add(NearbyUsersFilterChanged(filter)),
                ),

              // Main content
              Expanded(
                child: _buildContent(context, state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, NearbyUsersState state) {
    switch (state.status) {
      case NearbyUsersStatus.loading:
        return const Center(
          child: CircularProgressIndicator(),
        );

      case NearbyUsersStatus.error:
        return _ErrorState(
          message: state.errorMessage ?? 'An error occurred',
          onRetry: _startDiscovery,
        );

      case NearbyUsersStatus.empty:
        return NearbyUsersEmptyState(
          isScanning: state.isDiscovering,
          onRetry: state.isDiscovering
              ? null
              : () => context
                  .read<NearbyUsersBloc>()
                  .add(const NearbyUsersRefresh()),
        );

      case NearbyUsersStatus.idle:
      case NearbyUsersStatus.discovering:
        if (state.filteredUsers.isEmpty && state.users.isNotEmpty) {
          // Users exist but filter hides them
          return _NoFilterResults(
            onClearFilter: () => context
                .read<NearbyUsersBloc>()
                .add(const NearbyUsersFilterChanged(NearbyUsersFilter.all)),
          );
        }

        if (state.filteredUsers.isEmpty) {
          return NearbyUsersEmptyState(
            isScanning: state.isDiscovering,
            onRetry: state.isDiscovering
                ? null
                : () => context
                    .read<NearbyUsersBloc>()
                    .add(const NearbyUsersRefresh()),
          );
        }

        return _NearbyUsersList(
          users: state.filteredUsers,
          isDiscovering: state.isDiscovering,
        );
    }
  }
}

/// Nearby users list with smooth scrolling.
class _NearbyUsersList extends StatelessWidget {
  final List<NearbyUser> users;
  final bool isDiscovering;

  const _NearbyUsersList({
    required this.users,
    required this.isDiscovering,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<NearbyUsersBloc>().add(const NearbyUsersRefresh());
        // Wait a bit for UI feedback
        await Future.delayed(const Duration(seconds: 1));
      },
      child: ListView.builder(
        // Performance optimizations
        itemCount: users.length + 1, // +1 for footer
        itemExtent: null, // Let items size themselves
        cacheExtent: 200, // Cache items off-screen
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemBuilder: (context, index) {
          if (index == users.length) {
            // Footer with count
            return _ListFooter(
              count: users.length,
              isScanning: isDiscovering,
            );
          }

          final user = users[index];

          // Use RepaintBoundary for smoother scrolling
          return RepaintBoundary(
            child: NearbyUserCard(
              key: ValueKey(user.userId),
              user: user,
              onTap: () => _showUserDetails(context, user),
              onConnect: user.isConnected
                  ? null
                  : () => _connectWithUser(context, user),
            ),
          );
        },
      ),
    );
  }

  void _showUserDetails(BuildContext context, NearbyUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserDetailsSheet(user: user),
    );
  }

  void _connectWithUser(BuildContext context, NearbyUser user) {
    // TODO: Implement connection request
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connection request sent to ${user.displayName}'),
      ),
    );
  }
}

/// List footer showing count and scanning status.
class _ListFooter extends StatelessWidget {
  final int count;
  final bool isScanning;

  const _ListFooter({
    required this.count,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            '$count ${count == 1 ? 'person' : 'people'} nearby',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (isScanning) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Scanning...',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Error state widget.
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

    // Check if error message suggests Bluetooth or permission issue
    final isBluetoothOrPermissionIssue =
        message.toLowerCase().contains('bluetooth') ||
            message.toLowerCase().contains('permission') ||
            message.toLowerCase().contains('location');

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
              'Something went wrong',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
            if (isBluetoothOrPermissionIssue) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await openAppSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// No results for current filter.
class _NoFilterResults extends StatelessWidget {
  final VoidCallback onClearFilter;

  const _NoFilterResults({required this.onClearFilter});

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
              Icons.filter_list_off,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No users match this filter',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClearFilter,
              child: const Text('Show all'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet showing user details.
class _UserDetailsSheet extends StatelessWidget {
  final NearbyUser user;

  const _UserDetailsSheet({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Avatar
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          (user.displayName ?? 'U')[0].toUpperCase(),
                          style: theme.textTheme.headlineLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // Name
              Center(
                child: Text(
                  user.displayName ?? 'Unknown User',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Proximity
              Center(
                child: Chip(
                  avatar: Icon(
                    Icons.radar,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(
                    '${user.proximity.displayName} (~${user.estimatedDistance.toStringAsFixed(1)}m)',
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Bio
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                Text(
                  'About',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.bio!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Connect button
              if (!user.isConnected)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: Send connection request
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Connect'),
                )
              else
                Builder(
                  builder: (builderContext) {
                    // Get current user ID from AuthBloc
                    final authState = builderContext.read<AuthBloc>().state;
                    final currentUserId =
                        authState is AuthAuthenticated ? authState.user.id : '';

                    return OutlinedButton.icon(
                      onPressed: () {
                        // Capture navigation data before popping
                        final conversationId =
                            Conversation.createConversationId(
                          currentUserId,
                          user.userId,
                        );
                        final routeExtra = {
                          'currentUserId': currentUserId,
                          'otherUserId': user.userId,
                          'otherUserName': user.displayName ?? 'Unknown',
                          'otherUserPhotoUrl': user.photoUrl,
                        };
                        final route = Routes.chatWith(conversationId);

                        // Pop first, then navigate using the parent context
                        Navigator.pop(builderContext);

                        // Use a post-frame callback to ensure navigation happens
                        // after the bottom sheet is fully dismissed
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          // Check if the parent navigator context is still valid
                          if (context.mounted) {
                            context.push(route, extra: routeExtra);
                          }
                        });
                      },
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('Message'),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
