import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/firebase/firestore_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../nearby_help/data/nearby_help_service.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../data/connection_service.dart';
import '../../domain/entities/connection.dart';
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
        final isOnline = (doc['isOnline'] as bool?) ?? false;
        final lastSeenRaw = doc['lastSeen'];
        final lastSeen =
            lastSeenRaw is DateTime ? lastSeenRaw : lastSeenRaw?.toDate();

        normalized = {
          'id': widget.otherUserId,
          'displayName': displayName,
          'photoUrl': photoUrl,
          'bio': bio,
          'vibe': vibe,
          'mood': mood,
          'gender': gender,
          'isOnline': isOnline,
          'lastSeen': lastSeen,
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

    // Not connected — show Connect button
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
    final gender = profile['gender'] as String?;
    final isOnline = (profile['isOnline'] as bool?) ?? false;
    final lastSeen = profile['lastSeen'] as DateTime?;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 60,
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
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 40,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              displayName,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              isOnline
                  ? 'Online'
                  : lastSeen != null
                      ? 'Last seen ${_formatLastSeen(lastSeen)}'
                      : 'Offline',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isOnline
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isOnline ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (bio?.isNotEmpty == true)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  bio!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Center(
              child: Text(
                'No bio set',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 32),
          // Stats — Connections count & Helps Done count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              StreamBuilder<List<Connection>>(
                stream: getIt<ConnectionService>()
                    .getConnectionsStream(widget.otherUserId),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return _StatItem(
                    label: 'Connections',
                    value: count.toString(),
                  );
                },
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
          const SizedBox(height: 24),
          // Profile Fields
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileField(
                    icon: Icons.mood,
                    label: 'Vibe',
                    value: vibe,
                  ),
                  const Divider(height: 24),
                  _ProfileField(
                    icon: Icons.sentiment_satisfied_alt,
                    label: 'Mood',
                    value: mood,
                  ),
                  const Divider(height: 24),
                  _ProfileField(
                    icon: Icons.person_outline,
                    label: 'Gender',
                    value: gender,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          BlocConsumer<DiscoveryBloc, DiscoveryState>(
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
                  final isConnected =
                      connectionState.isConnectedWith(widget.otherUserId);
                  final existingSentRequest =
                      discoveryState.getSentRequestTo(widget.otherUserId) ??
                          connectionState.getSentRequestTo(widget.otherUserId);
                  final existingReceivedRequest =
                      discoveryState.getReceivedRequestFrom(widget.otherUserId) ??
                          connectionState.getReceivedRequestFrom(widget.otherUserId);

                  return Row(
                    children: [
                      Expanded(
                        child: _buildConnectionButton(
                          context,
                          isConnected: isConnected,
                          existingSentRequest: existingSentRequest,
                          existingReceivedRequest: existingReceivedRequest,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmBlock(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          icon: const Icon(Icons.block),
                          label: const Text('Block'),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.day}/${time.month}/${time.year}';
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
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;

  const _ProfileField({
    required this.icon,
    required this.label,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value?.isNotEmpty == true;

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasValue ? value! : 'Not set',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: hasValue
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
