import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/firebase/firestore_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../nearby_help/data/nearby_help_service.dart';
import '../../../local_news/presentation/widgets/user_news_posts_grid.dart';
import '../../../posts/presentation/bloc/user_posts_bloc.dart';
import '../../../posts/presentation/widgets/user_posts_grid.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../../profile/presentation/widgets/mood_selector.dart';
import '../../domain/entities/connection_request.dart';
import '../bloc/connection_bloc.dart';
import '../bloc/discovery_bloc.dart';

/// Page showing another user's public profile and connection actions.
class ConnectionProfilePage extends StatefulWidget {
  final String otherUserId;
  final String? initialName;
  final String? initialPhotoUrl;

  const ConnectionProfilePage({
    super.key,
    required this.otherUserId,
    this.initialName,
    this.initialPhotoUrl,
  });

  @override
  State<ConnectionProfilePage> createState() => _ConnectionProfilePageState();
}

class _ConnectionProfilePageState extends State<ConnectionProfilePage> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSendingRequest = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _initDiscoveryBloc();
  }

  void _initDiscoveryBloc() {
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
    }
  }

  Future<void> _loadProfile() async {
    try {
      final doc = await getIt<FirestoreService>()
          .getDocument('profiles/${widget.otherUserId}')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );

      Map<String, dynamic> normalized;
      if (doc == null) {
        normalized = {
          'id': widget.otherUserId,
          'displayName': widget.initialName ?? 'User',
          'photoUrl': widget.initialPhotoUrl,
          'bio': '',
          'vibe': '',
          'mood': '',
          'gender': null,
          'discoveryUsername': null,
          'isOnline': false,
          'lastSeen': null,
        };
      } else {
        final displayName =
            (doc['displayName'] as String?)?.trim().isNotEmpty == true
                ? (doc['displayName'] as String).trim()
                : (widget.initialName ?? 'User');

        final photoUrl = (doc['photoUrl'] as String?)?.trim().isNotEmpty == true
            ? (doc['photoUrl'] as String).trim()
            : widget.initialPhotoUrl;

        final bio = (doc['bio'] as String?)?.trim();
        final vibe = (doc['vibe'] as String?)?.trim();
        final mood = (doc['mood'] as String?)?.trim();
        final gender = (doc['gender'] as String?)?.trim();
        final discoveryUsername =
            (doc['discoveryUsername'] as String?)?.trim();

        normalized = {
          'id': widget.otherUserId,
          'displayName': displayName,
          'photoUrl': photoUrl,
          'bio': bio,
          'vibe': vibe,
          'mood': mood,
          'gender': gender,
          'discoveryUsername': discoveryUsername,
          'connectionCount': (doc['connectionCount'] as int?) ?? 0,
        };
      }

      if (mounted) {
        setState(() {
          _profile = normalized;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _profile = {
            'id': widget.otherUserId,
            'displayName': widget.initialName ?? 'User',
            'photoUrl': widget.initialPhotoUrl,
          };
          _isLoading = false;
        });
      }
    }
  }

  void _confirmRemove(BuildContext context) {
    final theme = Theme.of(context);
    final connectionState = context.read<ConnectionBloc>().state;
    final connection =
        connectionState.getConnectionWith(widget.otherUserId);
    if (connection == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Connection?'),
        content: const Text(
          'You will no longer be connected with this user. '
          'You can reconnect by sending a new request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ConnectionBloc>().add(
                    ConnectionRemove(connection.id),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Connection removed'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _sendConnectRequest() {
    setState(() => _isSendingRequest = true);
    context.read<DiscoveryBloc>().add(
          DiscoverySendRequest(
            receiverId: widget.otherUserId,
            receiverDisplayName: _profile?['displayName'] as String?,
            receiverPhotoUrl: _profile?['photoUrl'] as String?,
          ),
        );
  }

  Widget _buildConnectionButton(
    BuildContext context, {
    required bool isConnected,
    required ConnectionRequest? existingSentRequest,
    required ConnectionRequest? existingReceivedRequest,
  }) {
    if (_isSendingRequest) {
      return const OutlinedButton(
        onPressed: null,
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (isConnected) {
      return OutlinedButton.icon(
        onPressed: () => _confirmRemove(context),
        icon: const Icon(Icons.person_remove),
        label: const Text('Remove'),
      );
    }

    if (existingReceivedRequest != null) {
      return FilledButton.tonalIcon(
        onPressed: () {
          context.read<ConnectionBloc>().add(
                ConnectionAcceptRequest(existingReceivedRequest.id),
              );
        },
        icon: const Icon(Icons.check),
        label: const Text('Accept'),
      );
    }

    if (existingSentRequest != null) {
      return OutlinedButton.icon(
        onPressed: () {
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
                    context.read<DiscoveryBloc>().add(
                          DiscoveryCancelRequest(existingSentRequest.id),
                        );
                  },
                  child: const Text('Cancel Request'),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.hourglass_top),
        label: const Text('Pending'),
      );
    }

    // Not connected â€” show Connect button
    return FilledButton.icon(
      onPressed: _sendConnectRequest,
      icon: const Icon(Icons.person_add),
      label: const Text('Connect'),
    );
  }

  void _confirmBlock(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block User?'),
        content: Text(
          'Blocking ${(_profile?['displayName'] as String?) ?? 'this user'} will prevent them from sending you messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ConnectionBloc>().add(
                    ConnectionBlockUser(
                      widget.otherUserId,
                      blockedName: _profile?['displayName'] as String?,
                    ),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('User blocked'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile ?? {};
    final displayName = profile['displayName'] as String? ?? 'User';
    final photoUrl = profile['photoUrl'] as String?;
    final bio = profile['bio'] as String?;
    final vibe = profile['vibe'] as String?;
    final mood = profile['mood'] as String?;
    final discoveryUsername = profile['discoveryUsername'] as String?;
    final connectionCount = (profile['connectionCount'] as int?) ?? 0;

    final usernameDisplay = (discoveryUsername != null &&
            discoveryUsername.isNotEmpty)
        ? discoveryUsername
        : displayName;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Text(
          '@$usernameDisplay',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      // Profile photo â€“ left aligned with purple border
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
                          backgroundColor: theme.colorScheme.primaryContainer,
                          backgroundImage: photoUrl != null
                              ? CachedNetworkImageProvider(photoUrl)
                              : null,
                          child: photoUrl == null
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color:
                                        theme.colorScheme.onPrimaryContainer,
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
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatItem(
                              label: 'Connections',
                              value: connectionCount.toString(),
                            ),
                            StreamBuilder<int>(
                              stream: getIt<NearbyHelpService>()
                                  .streamHelpsDoneCount(widget.otherUserId),
                              builder: (context, snapshot) {
                                final helpsDone = snapshot.data ?? 0;
                                return _StatItem(
                                  label: 'Helps Done',
                                  value: helpsDone.toString(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // â”€â”€ Name â”€â”€
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    displayName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // â”€â”€ Bio â”€â”€
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    bio?.isNotEmpty == true ? bio! : 'No bio yet',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: bio?.isNotEmpty == true
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontStyle: bio?.isNotEmpty == true
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ),

                // â”€â”€ Vibe & Mood â”€â”€
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      // Vibe
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.electric_bolt,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Vibe',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vibe?.isNotEmpty == true ? _stripEmoji(vibe!) : 'Not set',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: vibe?.isNotEmpty == true
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Mood
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.mood,
                                    size: 14,
                                    color: theme.colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Mood',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                mood?.isNotEmpty == true
                                    ? (MoodSelector.moods[mood!] ?? _stripEmoji(mood))
                                    : 'Not set',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: mood?.isNotEmpty == true
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // â”€â”€ Connect & Block buttons (hide for own profile) â”€â”€
                if (context.read<AuthBloc>().state
                    case AuthAuthenticated(:final user)
                    when user.id != widget.otherUserId)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BlocConsumer<DiscoveryBloc, DiscoveryState>(
                    listenWhen: (prev, curr) =>
                        (curr.errorMessage != null &&
                            prev.errorMessage != curr.errorMessage) ||
                        (curr.successMessage != null &&
                            prev.successMessage != curr.successMessage),
                    listener: (context, state) {
                      if (state.successMessage != null) {
                        setState(() => _isSendingRequest = false);
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(state.successMessage!),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      if (state.errorMessage != null) {
                        setState(() => _isSendingRequest = false);
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(state.errorMessage!),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    builder: (context, discoveryState) {
                      return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                        builder: (context, connectionState) {
                          final isConnected = connectionState
                              .isConnectedWith(widget.otherUserId);
                          final existingSentRequest =
                              discoveryState
                                      .getSentRequestTo(widget.otherUserId) ??
                                  connectionState
                                      .getSentRequestTo(widget.otherUserId);
                          final existingReceivedRequest =
                              discoveryState.getReceivedRequestFrom(
                                      widget.otherUserId) ??
                                  connectionState.getReceivedRequestFrom(
                                      widget.otherUserId);

                          return Row(
                            children: [
                              Expanded(
                                child: _buildConnectionButton(
                                  context,
                                  isConnected: isConnected,
                                  existingSentRequest: existingSentRequest,
                                  existingReceivedRequest:
                                      existingReceivedRequest,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _confirmBlock(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                  ),
                                  icon: const Icon(Icons.block, size: 18),
                                  label: const Text('Block'),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // â”€â”€ Tab bar (Posts) â”€â”€
                TabBar(
                  labelColor: theme.colorScheme.onSurface,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
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
          body: BlocBuilder<ConnectionBloc, ConnectionBlocState>(
            builder: (context, connectionState) {
              final isConnected =
                  connectionState.isConnectedWith(widget.otherUserId);
              final authState = context.read<AuthBloc>().state;
              final viewerId = authState is AuthAuthenticated
                  ? authState.user.id
                  : '';

              return TabBarView(
                children: [
                  // Posts tab
                  BlocProvider(
                    create: (_) => getIt<UserPostsBloc>()
                      ..add(UserPostsLoadRequested(
                        userId: widget.otherUserId,
                        viewerUserId: viewerId,
                        isConnection: isConnected,
                      )),
                    child: const UserPostsGrid(),
                  ),
                  // News tab
                  UserNewsPostsGrid(userId: widget.otherUserId),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Strips leading emoji + space from a string like 'ðŸ‘‹ Open to talk' â†’ 'Open to talk'.
String _stripEmoji(String s) {
  final idx = s.indexOf(' ');
  return idx > 0 ? s.substring(idx + 1) : s;
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
