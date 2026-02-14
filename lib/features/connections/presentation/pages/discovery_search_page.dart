import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../domain/entities/connection_request.dart';
import '../bloc/connection_bloc.dart';
import '../bloc/discovery_bloc.dart';

/// Page for searching users by discovery username and sending connection requests.
class DiscoverySearchPage extends StatefulWidget {
  const DiscoverySearchPage({super.key});

  @override
  State<DiscoverySearchPage> createState() => _DiscoverySearchPageState();
}

class _DiscoverySearchPageState extends State<DiscoverySearchPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initBloc();
  }

  void _initBloc() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final profileState = context.read<ProfileBloc>().state;
      String? displayName;
      String? photoUrl;
      if (profileState is ProfileLoaded) {
        displayName = profileState.profile.name;
        photoUrl = profileState.profile.photoUrl;
      }

      final bloc = context.read<DiscoveryBloc>();
      bloc.setCurrentUser(
        userId: authState.user.id,
        displayName: displayName,
        photoUrl: photoUrl,
      );
      bloc.add(DiscoveryLoadRequests(
        authState.user.id,
        displayName: displayName,
        photoUrl: photoUrl,
      ));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      context.read<DiscoveryBloc>().add(DiscoverySearchUser(query));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Find People',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          BlocBuilder<DiscoveryBloc, DiscoveryState>(
            buildWhen: (prev, curr) =>
                prev.receivedRequests.length != curr.receivedRequests.length,
            builder: (context, state) {
              final count = state.receivedRequests.length;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.mail_outline),
                    onPressed: () =>
                        context.push(Routes.discoveryRequests),
                    tooltip: 'Discovery Requests',
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          count > 99 ? '99+' : count.toString(),
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
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Text(
                    '@',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Search by username...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline
                              .withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 14,
                        ),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  BlocBuilder<DiscoveryBloc, DiscoveryState>(
                    buildWhen: (prev, curr) =>
                        prev.searchQuery != curr.searchQuery,
                    builder: (context, state) {
                      if (state.searchQuery.isNotEmpty) {
                        return IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            context
                                .read<DiscoveryBloc>()
                                .add(const DiscoveryClearSearch());
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _performSearch,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Results
          Expanded(
            child: BlocConsumer<DiscoveryBloc, DiscoveryState>(
              listenWhen: (prev, curr) =>
                  (curr.errorMessage != null &&
                      prev.errorMessage != curr.errorMessage) ||
                  (curr.successMessage != null &&
                      prev.successMessage != curr.successMessage),
              listener: (context, state) {
                if (state.errorMessage != null) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.errorMessage!),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                if (state.successMessage != null) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.successMessage!),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state.status == DiscoveryStatus.searching) {
                  return const Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (state.status == DiscoveryStatus.searchNoResult) {
                  return _EmptySearchState(query: state.searchQuery);
                }

                if (state.status == DiscoveryStatus.searchResult) {
                  return _SearchResultsList(
                    results: state.searchResults,
                    state: state,
                  );
                }

                if (state.status == DiscoveryStatus.searchError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.errorMessage ?? 'Search failed',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                // Initial / loaded state - show hint
                return _InitialHint();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialHint extends StatelessWidget {
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
              Icons.person_search_outlined,
              size: 64,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Search by Discovery Username',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter a username to find and connect\nwith other users.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final String query;

  const _EmptySearchState({required this.query});

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
              Icons.search_off,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No user found',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'No user with username "@$query" was found.\nCheck the spelling and try again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  final List<Map<String, dynamic>> results;
  final DiscoveryState state;

  const _SearchResultsList({
    required this.results,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final user = results[index];
        return _UserResultCard(
          user: user,
          state: state,
        );
      },
    );
  }
}

class _UserResultCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final DiscoveryState state;

  const _UserResultCard({
    required this.user,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = user['userId'] as String;
    final displayName = user['displayName'] as String? ?? 'User';
    final discoveryUsername = user['discoveryUsername'] as String? ?? '';
    final photoUrl = user['photoUrl'] as String?;
    final bio = user['bio'] as String?;

    final isLoading =
        state.isActionLoading && state.processingId == userId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          Routes.userProfileWith(userId),
          extra: {
            'displayName': displayName,
            'photoUrl': photoUrl,
          },
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: photoUrl != null
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: photoUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _Initials(displayName),
                          errorWidget: (_, __, ___) =>
                              _Initials(displayName),
                        ),
                      )
                    : _Initials(displayName),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (discoveryUsername.isNotEmpty)
                      Text(
                        '@$discoveryUsername',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Action button — BlocBuilder ensures proper reactivity
              // to ConnectionBloc state changes (new connections, request
              // updates) that would otherwise be missed by context.watch.
              BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                builder: (context, connectionState) {
                  final isConnected =
                      connectionState.isConnectedWith(userId);
                  final existingSentRequest =
                      state.getSentRequestTo(userId) ??
                          connectionState.getSentRequestTo(userId);
                  final existingReceivedRequest =
                      state.getReceivedRequestFrom(userId) ??
                          connectionState.getReceivedRequestFrom(userId);

                  return _ActionButton(
                    userId: userId,
                    displayName: displayName,
                    photoUrl: photoUrl,
                    discoveryUsername: discoveryUsername,
                    isConnected: isConnected,
                    existingSentRequest: existingSentRequest,
                    existingReceivedRequest: existingReceivedRequest,
                    isLoading: isLoading,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;

  const _Initials(this.name);

  @override
  Widget build(BuildContext context) {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String discoveryUsername;
  final bool isConnected;
  final ConnectionRequest? existingSentRequest;
  final ConnectionRequest? existingReceivedRequest;
  final bool isLoading;

  const _ActionButton({
    required this.userId,
    required this.displayName,
    required this.photoUrl,
    required this.discoveryUsername,
    required this.isConnected,
    required this.existingSentRequest,
    required this.existingReceivedRequest,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (isConnected) {
      return Chip(
        label: const Text('Connected'),
        avatar: const Icon(Icons.check, size: 16),
        visualDensity: VisualDensity.compact,
      );
    }

    if (existingReceivedRequest != null) {
      return FilledButton.tonal(
        onPressed: () {
          context.read<DiscoveryBloc>().add(
                DiscoveryAcceptRequest(existingReceivedRequest!.id),
              );
        },
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('Accept'),
      );
    }

    if (existingSentRequest != null) {
      return OutlinedButton(
        onPressed: () {
          // Allow cancel
          showDialog(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: const Text('Cancel Request?'),
              content: const Text('The request will be cancelled.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Keep'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    context
                        .read<DiscoveryBloc>()
                        .add(DiscoveryCancelRequest(existingSentRequest!.id));
                  },
                  child: const Text('Cancel Request'),
                ),
              ],
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
        child: const Text('Pending'),
      );
    }

    // No connection / request - show Connect button
    return FilledButton(
      onPressed: () {
        context.read<DiscoveryBloc>().add(
              DiscoverySendRequest(
                receiverId: userId,
                receiverDisplayName: displayName,
                receiverPhotoUrl: photoUrl,
                receiverDiscoveryUsername: discoveryUsername,
              ),
            );
      },
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        visualDensity: VisualDensity.compact,
      ),
      child: const Text('Connect'),
    );
  }
}
