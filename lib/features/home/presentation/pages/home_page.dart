import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../chat/data/chat_service.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../connections/presentation/bloc/connection_bloc.dart';
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
                // Status card
                _BluetoothStatusCard(
                  isEnabled: _bluetoothEnabled,
                  isChecking: _checkingBluetooth,
                  onRefresh: _checkBluetoothStatus,
                  onEnableTap: _requestBluetoothOn,
                ),
                const SizedBox(height: 16),

                // Mood selector
                const MoodSelector(showLabel: true, compact: false),
                const SizedBox(height: 16),

                // Quick action buttons row
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => context.push(Routes.nearby),
                        icon: const Icon(Icons.radar),
                        label: const Text('Nearby'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                        builder: (context, connectionState) {
                          final pendingCount =
                              connectionState.receivedRequests.length;
                          return FilledButton.tonalIcon(
                            onPressed: () => context.push(Routes.connections),
                            icon: Badge(
                              isLabelVisible: pendingCount > 0,
                              label: Text(pendingCount.toString()),
                              child: const Icon(Icons.people),
                            ),
                            label: const Text('Connections'),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // GuessMe game button
                FilledButton.tonalIcon(
                  onPressed: () => context.push(Routes.guessme),
                  icon: const Icon(Icons.psychology),
                  label: const Text('Guess Me - Anonymous Chat Game'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor:
                        Theme.of(context).colorScheme.tertiaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 12),

                // Location Groups button
                FilledButton.tonalIcon(
                  onPressed: () => context.push(Routes.locationGroups),
                  icon: const Icon(Icons.location_on),
                  label: const Text('Location Groups'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
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

/// Widget that displays recent conversations (connections with recent messages)
class _RecentConversationsList extends StatelessWidget {
  final String userId;

  const _RecentConversationsList({required this.userId});

  @override
  Widget build(BuildContext context) {
    final chatService = getIt<ChatService>();

    return StreamBuilder<List<Conversation>>(
      stream: chatService.getConversationsStream(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
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

        final conversations = snapshot.data ?? [];
        
        // Take only the first 10 conversations
        final recentConversations = conversations.take(10).toList();

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
            final otherParticipant = conversation.getOtherParticipantInfo(userId);
            final otherUserId = conversation.getOtherParticipantId(userId);
            final unreadCount = conversation.getUnreadCount(userId);

            return _ConversationTile(
              conversation: conversation,
              otherParticipant: otherParticipant,
              otherUserId: otherUserId,
              currentUserId: userId,
              unreadCount: unreadCount,
            );
          },
        );
      },
    );
  }
}

/// Individual conversation tile
class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final ParticipantInfo? otherParticipant;
  final String otherUserId;
  final String currentUserId;
  final int unreadCount;

  const _ConversationTile({
    required this.conversation,
    required this.otherParticipant,
    required this.otherUserId,
    required this.currentUserId,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = otherParticipant?.displayName ?? 'Unknown';
    final photoUrl = otherParticipant?.photoUrl;
    final lastMessage = conversation.lastMessageText ?? 'No messages yet';
    final lastMessageTime = conversation.lastMessageAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: photoUrl == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
          if (unreadCount > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unreadCount > 9 ? '9+' : unreadCount.toString(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        displayName,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        lastMessage,
        style: theme.textTheme.bodySmall?.copyWith(
          color: unreadCount > 0
              ? theme.colorScheme.onSurface
              : theme.colorScheme.outline,
          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: lastMessageTime != null
          ? Text(
              _formatTime(lastMessageTime),
              style: theme.textTheme.labelSmall?.copyWith(
                color: unreadCount > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            )
          : null,
      onTap: () {
        context.push(
          Routes.chatWith(conversation.id),
          extra: {
            'currentUserId': currentUserId,
            'otherUserId': otherUserId,
            'otherUserName': displayName,
            'otherUserPhotoUrl': photoUrl,
          },
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);

    if (messageDate == today) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (messageDate == yesterday) {
      return 'Yesterday';
    }

    final daysAgo = today.difference(messageDate).inDays;
    if (daysAgo < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[time.weekday - 1];
    }

    return '${time.day}/${time.month}/${time.year}';
  }
}

/// Bluetooth status card widget showing current state.
class _BluetoothStatusCard extends StatelessWidget {
  final bool isEnabled;
  final bool isChecking;
  final VoidCallback onRefresh;
  final VoidCallback onEnableTap;

  const _BluetoothStatusCard({
    required this.isEnabled,
    required this.isChecking,
    required this.onRefresh,
    required this.onEnableTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusText = isChecking
        ? 'Checking...'
        : isEnabled
            ? 'Ready'
            : 'Off';

    final statusColor = isChecking
        ? theme.colorScheme.surfaceContainerHighest
        : isEnabled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.errorContainer;

    final statusTextColor = isChecking
        ? theme.colorScheme.onSurface
        : isEnabled
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onErrorContainer;

    final iconColor = isChecking
        ? theme.colorScheme.outline
        : isEnabled
            ? theme.colorScheme.primary
            : theme.colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isEnabled ? Icons.bluetooth : Icons.bluetooth_disabled,
                  color: iconColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Bluetooth Status',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isChecking
                      ? Padding(
                          key: const ValueKey('checking'),
                          padding: const EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('refresh'),
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: onRefresh,
                          tooltip: 'Refresh Bluetooth status',
                          visualDensity: VisualDensity.compact,
                        ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!isEnabled && !isChecking) ...[
              Text(
                'Please turn on Bluetooth to discover nearby users',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onEnableTap,
                icon: const Icon(Icons.bluetooth),
                label: const Text('Turn On Bluetooth'),
              ),
            ] else
              const Text('Tap below to start scanning for nearby users'),
          ],
        ),
      ),
    );
  }
}
