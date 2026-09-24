import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
import '../../../nearby_help/data/nearby_help_service.dart';
import '../../../local_news/presentation/widgets/user_news_posts_grid.dart';
import '../../../posts/presentation/bloc/user_posts_bloc.dart';
import '../../../posts/presentation/widgets/user_posts_grid.dart';
import '../bloc/profile_bloc.dart';

/// Page showing the current user's own public profile in the same
/// Instagram-style layout used for other users' profiles.
class OwnPublicProfilePage extends StatefulWidget {
  const OwnPublicProfilePage({super.key});

  @override
  State<OwnPublicProfilePage> createState() => _OwnPublicProfilePageState();
}

class _OwnPublicProfilePageState extends State<OwnPublicProfilePage> {
  @override
  void initState() {
    super.initState();
    // Ensure profile is loaded when this page opens (e.g. from bottom nav)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        context
            .read<ProfileBloc>()
            .add(ProfileLoadRequested(authState.user.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user =
            authState is AuthAuthenticated ? authState.user : null;
        if (user == null) {
          return const Scaffold(
            body: Center(child: Text('Not signed in')),
          );
        }

        return BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, profileState) {
            String displayName = user.displayName ?? 'User';
            String? photoUrl = user.avatarUrl;
            String bio = '';
            String? vibe;
            String? mood;
            String? discoveryUsername;

            if (profileState is ProfileLoaded) {
              final p = profileState.profile;
              if (p.name.isNotEmpty) displayName = p.name;
              if (p.photoUrl != null && p.photoUrl!.isNotEmpty) {
                photoUrl = p.photoUrl;
              }
              bio = p.bio;
              vibe = p.vibe;
              mood = p.mood;
              discoveryUsername = p.discoveryUsername;
            }

            final usernameDisplay =
                (discoveryUsername != null && discoveryUsername.isNotEmpty)
                    ? discoveryUsername
                    : displayName;

            return Scaffold(
              appBar: AppBar(
                centerTitle: false,
                titleSpacing: 16,
                title: Text(
                  '@$usernameDisplay',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () => context.push(Routes.settings),
                  ),
                ],
              ),
              body: DefaultTabController(
                length: 2,
                child: NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // â”€â”€ Header row: avatar + stats â”€â”€
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            child: Row(
                              children: [
                                // Profile photo with purple border
                                Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.purple,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 42,
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    backgroundImage: photoUrl != null
                                        ? CachedNetworkImageProvider(photoUrl)
                                        : null,
                                    child: photoUrl == null
                                        ? Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: theme.colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 32,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                // Stats
                                Expanded(
                                  child: BlocBuilder<ConnectionBloc,
                                      ConnectionBlocState>(
                                    builder: (context, connectionState) {
                                      final connectionsCount =
                                          connectionState.connections.length;
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          _StatItem(
                                            label: 'Connections',
                                            value:
                                                connectionsCount.toString(),
                                          ),
                                          StreamBuilder<int>(
                                            stream:
                                                getIt<NearbyHelpService>()
                                                    .streamHelpsDoneCount(
                                                        user.id),
                                            builder: (context, snapshot) {
                                              final helpsDone =
                                                  snapshot.data ?? 0;
                                              return _StatItem(
                                                label: 'Helps Done',
                                                value:
                                                    helpsDone.toString(),
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // â”€â”€ Name â”€â”€
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              displayName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          // â”€â”€ Bio â”€â”€
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: Text(
                              bio.isNotEmpty ? bio : 'No bio yet',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: bio.isNotEmpty
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                                fontStyle: bio.isNotEmpty
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                              ),
                            ),
                          ),

                          // â”€â”€ Vibe & Mood â”€â”€
                          if ((vibe?.isNotEmpty == true) || (mood?.isNotEmpty == true))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (vibe?.isNotEmpty == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: theme.colorScheme.primary.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.electric_bolt,
                                            size: 14,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            vibe!,
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (mood?.isNotEmpty == true)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: theme.colorScheme.secondary.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.mood,
                                            size: 14,
                                            color: theme.colorScheme.secondary,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            mood!,
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              color: theme.colorScheme.secondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 12),

                          // â”€â”€ Edit Profile button â”€â”€
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    context.push(Routes.editProfile),
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18),
                                label: const Text('Edit Profile'),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // â”€â”€ Tab bar â”€â”€
                          TabBar(
                            labelColor: theme.colorScheme.onSurface,
                            unselectedLabelColor:
                                theme.colorScheme.onSurfaceVariant,
                            indicatorColor: theme.colorScheme.primary,
                            tabs: const [
                              Tab(icon: Icon(Icons.grid_on_outlined)),
                              Tab(icon: Icon(Icons.newspaper_outlined)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  body: TabBarView(
                    children: [
                      // Posts tab â€” own profile sees all posts
                      BlocProvider(
                        create: (_) => getIt<UserPostsBloc>()
                          ..add(UserPostsLoadRequested(
                            userId: user.id,
                            viewerUserId: user.id,
                            isConnection: false,
                          )),
                        child: const UserPostsGrid(),
                      ),
                      // News tab
                      UserNewsPostsGrid(userId: user.id),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}


class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
