import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/services/firebase/firestore_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/connection_service.dart';
import '../../domain/entities/connection.dart';
import '../bloc/connection_bloc.dart';

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
  Connection? _connection;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadConnection();
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

  Future<void> _loadConnection() async {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) return;

      final connectionService = getIt<ConnectionService>();
      final connection = await connectionService.getConnection(
        authState.user.id,
        widget.otherUserId,
      );
      if (mounted) {
        setState(() => _connection = connection);
      }
    } catch (_) {
      // ignore
    }
  }

  void _confirmRemove(BuildContext context) {
    final theme = Theme.of(context);
    if (_connection == null) return;

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
                    ConnectionRemove(_connection!.id),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Connection removed'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: theme.colorScheme.error,
                ),
              );
              Navigator.of(context).pop();
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
                    ConnectionBlockUser(widget.otherUserId),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _connection == null
                      ? null
                      : () => _confirmRemove(context),
                  icon: const Icon(Icons.person_remove),
                  label: const Text('Remove'),
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
