import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../domain/entities/guess_me_stats.dart';
import '../bloc/guess_me_bloc.dart';
import '../widgets/guess_me_badge_widget.dart';

/// The lobby screen for GuessMe feature.
/// Shows queue status, stats, and badge information.
class GuessMeLobbyPage extends StatefulWidget {
  const GuessMeLobbyPage({super.key});

  @override
  State<GuessMeLobbyPage> createState() => _GuessMeLobbyPageState();
}

class _GuessMeLobbyPageState extends State<GuessMeLobbyPage> {
  bool _isScanning = false;
  bool _hasScanned = false;

  @override
  void initState() {
    super.initState();
    _initializeGuessMe();
    _startInitialScan();
  }

  void _initializeGuessMe() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<GuessmeBloc>().add(GuessmeInitialize(authState.user.id));
    }
  }

  /// Starts a BLE scan when the page loads
  void _startInitialScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      // Ensure advertising is initialized before scanning
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final nearbyBloc = context.read<NearbyUsersBloc>();
        
        // Initialize if not already initialized
        nearbyBloc.add(NearbyUsersInitialize(
          userId: authState.user.id,
          username: authState.user.username,
        ));
        
        // Wait a moment for initialization, then start scan
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _startScan();
          }
        });
      }
    });
  }

  /// Triggers a BLE scan for nearby users
  void _startScan() {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _hasScanned = true;
    });

    final nearbyBloc = context.read<NearbyUsersBloc>();
    nearbyBloc.add(const NearbyUsersStartScan());

    // Scanning takes 15 seconds, update UI after that
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        
        // Check if scan found users
        final nearbyState = nearbyBloc.state;
        if (nearbyState.status == NearbyUsersStatus.error) {
          _showScanError(nearbyState.errorMessage);
        } else if (nearbyState.users.isEmpty) {
          _showNoUsersFound();
        }
      }
    });
  }
  
  /// Show error message when scan fails
  void _showScanError(String? errorMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? 'Failed to scan for nearby users'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _startScan,
        ),
      ),
    );
  }
  
  /// Show message when no users found after scan
  void _showNoUsersFound() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('No players found nearby. Make sure Bluetooth is enabled.'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Scan Again',
          textColor: Colors.white,
          onPressed: _startScan,
        ),
      ),
    );
  }

  void _joinQueue() {
    // If still scanning, wait for it to complete
    if (_isScanning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scanning for nearby users... Please wait.'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final nearbyState = context.read<NearbyUsersBloc>().state;
    final nearbyUserIds = nearbyState.users
        .where((u) => u.userId != null)
        .map((u) => u.userId!)
        .toList();

    if (nearbyUserIds.isEmpty) {
      // Offer to scan again
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No nearby users found. Try scanning again?'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Scan',
            textColor: Colors.white,
            onPressed: _startScan,
          ),
        ),
      );
      return;
    }

    context.read<GuessmeBloc>().add(GuessmeJoinQueue(nearbyUserIds));
  }

  void _leaveQueue() {
    context.read<GuessmeBloc>().add(const GuessmeLeaveQueue());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guess Me'),
        centerTitle: true,
      ),
      body: BlocConsumer<GuessmeBloc, GuessmeState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) {
          // Navigate to game screen when matched
          if (state.status == GuessmeStatus.inGame && state.session != null) {
            context.push(
              Routes.guessmeGame,
              extra: {'sessionId': state.session!.id},
            );
          }

          // Show error messages
          if (state.status == GuessmeStatus.error &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.status == GuessmeStatus.loading ||
              state.status == GuessmeStatus.initial) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async => _initializeGuessMe(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header card explaining the game
                  _buildInfoCard(context),
                  const SizedBox(height: 24),
                  // Scanning status indicator
                  if (_isScanning) ...[
                    _buildScanningIndicator(context),
                    const SizedBox(height: 24),
                  ],
                  // Active games section (if any)
                  if (state.session != null &&
                      (state.status == GuessmeStatus.inGame ||
                          state.status == GuessmeStatus.awaitingGuessResponse ||
                          state.status ==
                              GuessmeStatus.receivedGuessCheck)) ...[
                    _buildActiveGamesSection(context, state),
                    const SizedBox(height: 24),
                  ],

                  // Stats card
                  if (state.stats != null) ...[
                    _buildStatsCard(context, state.stats!),
                    const SizedBox(height: 24),
                  ],

                  // Join queue / In queue section
                  _buildQueueSection(context, state),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.psychology,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'How to Play',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoItem(
              context,
              Icons.person_search,
              'Get matched with a nearby user anonymously',
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              Icons.chat_bubble_outline,
              'Chat for up to 1 hour without knowing who they are',
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              Icons.lightbulb_outline,
              'Think you know who it is? Use your "Guess Check"!',
            ),
            const SizedBox(height: 8),
            _buildInfoItem(
              context,
              Icons.emoji_events_outlined,
              'Correct guesses earn you badges visible to others',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.secondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveGamesSection(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final session = state.session!;
    final timeRemaining = session.timeRemaining;

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          context.push(
            Routes.guessmeGame,
            extra: {'sessionId': session.id},
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.games,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Active Game',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: theme.colorScheme.secondary,
                    child: const Text(
                      '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mystery Player',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${timeRemaining.inMinutes}m ${timeRemaining.inSeconds.remainder(60)}s remaining',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, GuessmeStats stats) {
    final theme = Theme.of(context);
    final badge = stats.badge;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bar_chart,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Your Stats',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (badge != GuessmeBadgeTier.none)
                  _buildBadgeChip(context, badge),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Games Played',
                    stats.gamesPlayed.toString(),
                    Icons.games,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Correct Guesses',
                    stats.correctGuesses.toString(),
                    Icons.check_circle_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Current Streak',
                    stats.currentStreak.toString(),
                    Icons.local_fire_department,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    context,
                    'Best Streak',
                    stats.bestStreak.toString(),
                    Icons.emoji_events,
                  ),
                ),
              ],
            ),
            if (badge != GuessmeBadgeTier.master) ...[
              const SizedBox(height: 16),
              _buildProgressToNextBadge(context, stats),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, size: 24, color: theme.colorScheme.secondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildBadgeChip(BuildContext context, GuessmeBadgeTier badge) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badge.color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            badge.icon,
            size: 16,
            color: badge.color,
          ),
          const SizedBox(width: 4),
          Text(
            badge.displayName,
            style: TextStyle(
              color: badge.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressToNextBadge(BuildContext context, GuessmeStats stats) {
    final theme = Theme.of(context);
    final nextBadge = stats.nextBadge;
    final progress = stats.progressToNextBadge;

    if (nextBadge == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress to ${nextBadge.displayName}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(nextBadge.color),
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildQueueSection(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final isInQueue = state.status == GuessmeStatus.inQueue;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isInQueue) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Finding a match...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Looking for nearby players',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _leaveQueue,
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ] else ...[
              Icon(
                Icons.play_circle_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Ready to play?',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Join the queue to get matched with a nearby user',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isScanning ? null : _joinQueue,
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(_isScanning ? 'Scanning...' : 'Find Match'),
              ),
              if (_hasScanned && !_isScanning) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Scan Again'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Build scanning indicator widget
  Widget _buildScanningIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final nearbyState = context.watch<NearbyUsersBloc>().state;
    final userCount = nearbyState.users.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scanning for nearby users...',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userCount > 0
                        ? 'Found $userCount ${userCount == 1 ? 'user' : 'users'} so far'
                        : 'Looking for players nearby',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
