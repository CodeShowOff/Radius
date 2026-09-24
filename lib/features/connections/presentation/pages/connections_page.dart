import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../data/connection_service.dart';
import '../bloc/connection_bloc.dart';
import '../bloc/suggested_connections_cubit.dart';
import '../bloc/suggested_connections_state.dart';
import '../../../chat/presentation/screens/conversations_screen.dart';

/// Connections page showing suggested connections and active chats.
class ConnectionsPage extends StatelessWidget {
  const ConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SuggestedConnectionsCubit(getIt<ConnectionService>()),
      child: const _ConnectionsView(),
    );
  }
}

class _ConnectionsView extends StatefulWidget {
  const _ConnectionsView();

  @override
  State<_ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends State<_ConnectionsView> {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    
    final connectionState = context.read<ConnectionBloc>().state;
    final authState = context.read<AuthBloc>().state;
    
    if (authState is AuthAuthenticated) {
      final currentUserId = authState.user.id;
      
      // Load People You May Know
      context.read<SuggestedConnectionsCubit>().loadSuggestions(currentUserId);
      
      final blocUserId = connectionState.userId;
      if (blocUserId == null || blocUserId != currentUserId) {
        if (connectionState.status == ConnectionBlocStatus.initial) {
          _loadConnections();
        }
      }
    }
  }

  void _loadConnections() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.read<AuthBloc>().state;
    final currentUserId = (authState is AuthAuthenticated) ? authState.user.id : '';

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              floating: true,
              pinned: true,
              elevation: 0,
              backgroundColor: theme.colorScheme.surface,
              surfaceTintColor: theme.colorScheme.surface,
              title: _isSearching
                  ? Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'Search network...',
                          hintStyle: TextStyle(color: theme.colorScheme.outline),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    )
                  : const Text('Connections'),
              actions: [
                if (_isSearching)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                      });
                    },
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Search Messages',
                    onPressed: () => setState(() => _isSearching = true),
                  ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt_1),
                  tooltip: 'Add Connection',
                  onPressed: () => context.push(Routes.discoverySearch),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (!_isSearching && _searchQuery.isEmpty)
              SliverToBoxAdapter(
                child: _buildSuggestedConnections(theme, currentUserId),
              ),
          ];
        },
        body: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: ConversationsScreen(
            currentUserId: currentUserId,
            onConversationTap: (channel) {
              final otherMember = channel.state?.members.firstWhere(
                (m) => m.userId != currentUserId,
                orElse: () => channel.state!.members.first,
              );

              context.push(
                Routes.chatWith(channel.id!),
                extra: {
                  'currentUserId': currentUserId,
                  'otherUserId': otherMember?.userId ?? '',
                  'otherUserName': otherMember?.user?.name ?? 'Unknown',
                  'otherUserPhotoUrl': otherMember?.user?.image,
                },
              );
            },
          ),
         ),
        ),
      ),
    );
  }

  Widget _buildSuggestedConnections(ThemeData theme, String currentUserId) {
    return BlocBuilder<SuggestedConnectionsCubit, SuggestedConnectionsState>(
      builder: (context, state) {
        if (state is SuggestedConnectionsLoading || state is SuggestedConnectionsInitial) {
          return const SizedBox.shrink();
        }

        if (state is SuggestedConnectionsError) {
          return const SizedBox.shrink();
        }

        if (state is SuggestedConnectionsLoaded) {
          if (state.suggestions.isEmpty) return const SizedBox.shrink();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Text(
                  'People You May Know',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.suggestions.length,
                  itemBuilder: (context, index) {
                    final user = state.suggestions[index];
                    return _SuggestedUserCard(
                      user: user,
                      currentUserId: currentUserId,
                    );
                  },
                ),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _SuggestedUserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final String currentUserId;

  const _SuggestedUserCard({required this.user, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = user['userId'] as String;
    final displayName = user['displayName'] as String? ?? 'User';
    final photoUrl = user['photoUrl'] as String?;
    final reason = user['reason'] as String? ?? 'Suggested for you';

    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          CachedAvatar(
            imageUrl: photoUrl,
            name: displayName,
            radius: 36,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              displayName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              reason,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: double.infinity,
              height: 32,
              child: FilledButton(
                onPressed: () {
                  context.read<ConnectionBloc>().add(ConnectionSendRequest(
                    receiverId: userId,
                    receiverDisplayName: displayName,
                    receiverPhotoUrl: photoUrl,
                    source: 'people_you_may_know',
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Request sent to $displayName')),
                  );
                },
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Connect', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
