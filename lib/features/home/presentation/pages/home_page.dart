import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/presentation/bloc/conversations_bloc.dart';
import '../../../chat/presentation/widgets/conversation_tile.dart';
import '../../../profile/presentation/bloc/profile_bloc.dart';
import '../../../profile/presentation/widgets/mood_selector.dart';

/// Home page - main screen after authentication.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _bluetoothEnabled = false;
  bool _checkingBluetooth = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBluetoothStatus();
    
    // Ensure conversations are loaded for the recent conversations list
    // The BLoC handles redundant loads gracefully - if already loaded,
    // this will be a no-op while keeping real-time streams active
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      final convState = context.read<ConversationsBloc>().state;
      // Only explicitly trigger load if in initial state
      // Otherwise, streams are already active from app initialization
      if (convState.status == ConversationsStatus.initial) {
        context.read<ConversationsBloc>().add(
              ConversationsLoad(userId: authState.user.id),
            );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check Bluetooth when app comes back to foreground
      _checkBluetoothStatus();
    }
  }

  Future<void> _checkBluetoothStatus() async {
    setState(() => _checkingBluetooth = true);
    try {
      final bluetoothService = context.read<BluetoothService>();
      final isEnabled = await bluetoothService.isBluetoothEnabled();
      if (mounted) {
        setState(() {
          _bluetoothEnabled = isEnabled;
          _checkingBluetooth = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bluetoothEnabled = false;
          _checkingBluetooth = false;
        });
      }
    }
  }

  Future<void> _requestBluetoothOn() async {
    try {
      final bluetoothService = context.read<BluetoothService>();
      await bluetoothService.requestBluetoothOn();
      // Wait a bit for Bluetooth to turn on
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkBluetoothStatus();
    } catch (e) {
      // Ignore errors
    }
  }

  void _showBluetoothPrompt(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth is Off'),
        content: const Text(
          'Please turn on Bluetooth to discover nearby users and use all features of Radius.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _requestBluetoothOn();
            },
            icon: const Icon(Icons.bluetooth),
            label: const Text('Turn On'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthUnauthenticated) {
          context.go(Routes.login);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Radius',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            // Bluetooth status icon
            IconButton(
              onPressed: () {
                if (!_bluetoothEnabled && !_checkingBluetooth) {
                  _showBluetoothPrompt(context);
                }
              },
              icon: Icon(
                _bluetoothEnabled ? Icons.bluetooth : Icons.bluetooth_disabled,
                color: _checkingBluetooth
                    ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                    : _bluetoothEnabled
                        ? Colors.blue
                        : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                size: 22,
              ),
              tooltip: _checkingBluetooth
                  ? 'Checking Bluetooth...'
                  : _bluetoothEnabled
                      ? 'Bluetooth is on'
                      : 'Bluetooth is off - Tap to enable',
            ),
            BlocBuilder<ProfileBloc, ProfileState>(
              builder: (context, profileState) {
                return BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, authState) {
                    String? photoUrl;
                    String displayName = 'U';

                    if (authState is AuthAuthenticated) {
                      photoUrl = authState.user.avatarUrl;
                      displayName = authState.user.displayName ?? 'U';
                    }

                    if (profileState is ProfileLoaded) {
                      if (profileState.profile.photoUrl != null &&
                          profileState.profile.photoUrl!.isNotEmpty) {
                        photoUrl = profileState.profile.photoUrl;
                      }
                      if (profileState.profile.name.isNotEmpty) {
                        displayName = profileState.profile.name;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        onPressed: () => context.push(Routes.profile),
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage:
                              photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mood selector
                const MoodSelector(showLabel: true, compact: false),
                const SizedBox(height: 16),

                // Quick action buttons row - Nearby and Guess Me
                Row(
                  children: [
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.nearby),
                        label: 'Nearby',
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        isSquare: true,
                        animationType: _CardAnimationType.wave,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AnimatedSquareCard(
                        onTap: () => context.push(Routes.guessme),
                        label: 'Guess Me',
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        isSquare: true,
                        animationType: _CardAnimationType.personCycle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Connections section header with "View All" button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Connections',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.connections),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Recent conversations list
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, authState) {
                    if (authState is! AuthAuthenticated) {
                      return const Expanded(
                        child: Center(
                          child: Text('Please sign in'),
                        ),
                      );
                    }

                    return Expanded(
                      child: _RecentConversationsList(
                        userId: authState.user.id,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget that displays recent conversations preview.
/// Uses ConversationsBloc as single source of truth.
class _RecentConversationsList extends StatelessWidget {
  final String userId;

  const _RecentConversationsList({required this.userId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConversationsBloc, ConversationsState>(
      builder: (context, state) {
        if (state.status == ConversationsStatus.loading &&
            state.conversations.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.status == ConversationsStatus.error &&
            state.conversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load conversations',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ],
            ),
          );
        }

        // Take only the first 10 conversations (preview)
        final recentConversations = state.conversations.take(10).toList();

        if (recentConversations.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  'No conversations yet',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect with people and start chatting',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: recentConversations.length,
          itemBuilder: (context, index) {
            final conversation = recentConversations[index];
            final otherUserId = conversation.getOtherParticipantId(userId);
            final otherParticipant = conversation.getOtherParticipantInfo(userId);

            return ConversationTile(
              conversation: conversation,
              currentUserId: userId,
              onTap: () {
                context.push(
                  Routes.chatWith(conversation.id),
                  extra: {
                    'currentUserId': userId,
                    'otherUserId': otherUserId,
                    'otherUserName': otherParticipant?.displayName ?? 'User',
                    'otherUserPhotoUrl': otherParticipant?.photoUrl,
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Simple card widget for home page action buttons.
class _AnimatedSquareCard extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final Color color;
  final Color backgroundColor;
  final bool isSquare;
  final _CardAnimationType animationType;

  const _AnimatedSquareCard({
    required this.onTap,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.isSquare = false,
    this.animationType = _CardAnimationType.wave,
  });

  IconData _getIcon() {
    switch (animationType) {
      case _CardAnimationType.wave:
        return Icons.radar;
      case _CardAnimationType.personCycle:
        return Icons.psychology;
      case _CardAnimationType.talking:
        return Icons.groups;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: backgroundColor,
        child: isSquare
            ? AspectRatio(
                aspectRatio: 1,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getIcon(),
                          size: 34,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        label,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                height: 80,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(),
                        size: 28,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

enum _CardAnimationType { wave, personCycle, talking }

