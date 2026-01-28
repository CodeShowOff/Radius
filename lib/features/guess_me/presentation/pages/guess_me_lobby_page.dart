import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/services/bluetooth/bluetooth_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../proximity/presentation/bloc/nearby_users_bloc.dart';
import '../../domain/entities/guess_me_stats.dart';
import '../bloc/guess_me_bloc.dart';
import '../widgets/guess_me_badge_widget.dart';

/// The lobby screen for GuessMe feature.
/// 
/// GAME FLOW:
/// 1. Page opens WITHOUT auto-scan - "Play Game" button is enabled
/// 2. User taps "Play Game" -> Scanning starts in background
/// 3. As soon as ANY nearby user is found -> Stop scan, instantly connect
/// 4. Create temporary anonymous chat session (1 hour duration)
/// 5. Either user can click "Guessed" to initiate guess check
/// 6. On correct guess -> Show congrats, ask BOTH users if they want to connect
/// 7. Only if BOTH agree -> Create permanent connection
class GuessMeLobbyPage extends StatefulWidget {
  const GuessMeLobbyPage({super.key});

  @override
  State<GuessMeLobbyPage> createState() => _GuessMeLobbyPageState();
}

class _GuessMeLobbyPageState extends State<GuessMeLobbyPage>
    with WidgetsBindingObserver {
  bool _bluetoothEnabled = false;
  bool _checkingBluetooth = true;
  bool _isSearching = false;
  int _scanRetryCount = 0;
  static const int _maxScanRetries = 5; // Maximum scan attempts before giving up
  StreamSubscription<NearbyUsersState>? _nearbyUsersSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeGuessMe();
    _checkBluetoothStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nearbyUsersSubscription?.cancel();
    _stopSearching();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBluetoothStatus();
    } else if (state == AppLifecycleState.paused) {
      // Stop searching when app goes to background
      if (_isSearching) {
        _stopSearching();
      }
    }
  }

  void _initializeGuessMe() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<GuessmeBloc>().add(GuessmeInitialize(authState.user.id));
    }
  }

  /// Check Bluetooth status without starting scan
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

  /// Request to turn on Bluetooth
  Future<void> _requestBluetoothOn() async {
    try {
      final bluetoothService = context.read<BluetoothService>();
      await bluetoothService.requestBluetoothOn();
      await Future.delayed(const Duration(milliseconds: 500));
      await _checkBluetoothStatus();
    } catch (e) {
      // Ignore errors
    }
  }

  /// Start the game - begins searching for a match
  /// This is the ONLY way scanning starts
  void _playGame() {
    if (_isSearching) return;
    
    if (!_bluetoothEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please turn on Bluetooth first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to play'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _scanRetryCount = 0; // Reset retry count on new search
    });

    // Mark user as searching in Firestore so other users can find them
    context.read<GuessmeBloc>().add(GuessmeMarkSearching(authState.user.id));

    final nearbyBloc = context.read<NearbyUsersBloc>();
    
    // Initialize advertising if not already
    nearbyBloc.add(NearbyUsersInitialize(
      userId: authState.user.id,
      username: authState.user.username,
    ));
    
    // Clear previous results
    nearbyBloc.add(const NearbyUsersClearResults());

    // Start scanning with 7-second duration
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || !_isSearching) return;
      
      // Start 7-second scan for GuessMe
      nearbyBloc.add(const NearbyUsersStartScan(
        duration: Duration(seconds: 7),
      ));
      
      // Listen for nearby users - connect to first one found
      _nearbyUsersSubscription?.cancel();
      _nearbyUsersSubscription = nearbyBloc.stream.listen((state) {
        if (!mounted || !_isSearching) return;
        
        // If we found any users, immediately try to match
        if (state.users.isNotEmpty) {
          final nearbyUserIds = state.users
              .where((u) => u.userId != null)
              .map((u) => u.userId!)
              .toList();
          
          if (nearbyUserIds.isNotEmpty) {
            _connectToMatch(nearbyUserIds);
          }
        }
        
        // Handle scan completion with no results (7 seconds elapsed, no users found)
        if (state.status == NearbyUsersStatus.empty && _isSearching) {
          _handleNoUsersFound();
        }
        
        // Handle errors
        if (state.status == NearbyUsersStatus.error) {
          _handleScanError(state.errorMessage);
        }
      });
    });
  }

  /// Stop searching for a match
  void _stopSearching() {
    if (!_isSearching) return;
    
    _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = null;
    
    final nearbyBloc = context.read<NearbyUsersBloc>();
    nearbyBloc.add(const NearbyUsersStopScan());
    
    // Clear searching status in Firestore
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      context.read<GuessmeBloc>().add(GuessmeClearSearching(authState.user.id));
    }
    
    if (mounted) {
      setState(() {
        _isSearching = false;
      });
    }
  }

  /// Connect to the first available user
  void _connectToMatch(List<String> nearbyUserIds) {
    if (!_isSearching) return;
    
    // Stop scanning immediately
    final nearbyBloc = context.read<NearbyUsersBloc>();
    nearbyBloc.add(const NearbyUsersStopScan());
    
    // Join queue with nearby users - service will create session immediately
    context.read<GuessmeBloc>().add(GuessmeJoinQueue(nearbyUserIds));
    
    _nearbyUsersSubscription?.cancel();
    _nearbyUsersSubscription = null;
    
    // Don't set _isSearching to false yet - wait for match confirmation
  }

  /// Handle when no users are found after scan completes
  void _handleNoUsersFound() {
    _stopSearching();
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('No players found nearby. Make sure Bluetooth is enabled on both devices.'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Try Again',
          textColor: Colors.white,
          onPressed: _playGame,
        ),
      ),
    );
  }

  /// Handle scan errors
  void _handleScanError(String? errorMessage) {
    _stopSearching();
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage ?? 'Failed to scan for nearby users'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _playGame,
        ),
      ),
    );
  }

  /// Continue scanning when users were found but not available for matching.
  /// This restarts the scan to find other nearby users or wait for them to start playing.
  void _continueScanning() {
    if (!_isSearching || !mounted) return;
    
    _scanRetryCount++;
    
    // Check if we've exceeded max retries
    if (_scanRetryCount >= _maxScanRetries) {
      _stopSearching();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No available players found. Make sure both devices tap "Play Game".'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Try Again',
              textColor: Colors.white,
              onPressed: _playGame,
            ),
          ),
        );
      }
      return;
    }
    
    final nearbyBloc = context.read<NearbyUsersBloc>();
    
    // Clear previous results to find fresh users
    nearbyBloc.add(const NearbyUsersClearResults());
    
    // Restart scan after a brief delay
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || !_isSearching) return;
      
      // Start another 7-second scan
      nearbyBloc.add(const NearbyUsersStartScan(
        duration: Duration(seconds: 7),
      ));
      
      // Re-subscribe to nearby users
      _nearbyUsersSubscription?.cancel();
      _nearbyUsersSubscription = nearbyBloc.stream.listen((state) {
        if (!mounted || !_isSearching) return;
        
        // If we found any users, immediately try to match
        if (state.users.isNotEmpty) {
          final nearbyUserIds = state.users
              .where((u) => u.userId != null)
              .map((u) => u.userId!)
              .toList();
          
          if (nearbyUserIds.isNotEmpty) {
            _connectToMatch(nearbyUserIds);
          }
        }
        
        // Handle scan completion with no results
        if (state.status == NearbyUsersStatus.empty && _isSearching) {
          _handleNoUsersFound();
        }
        
        // Handle errors
        if (state.status == NearbyUsersStatus.error) {
          _handleScanError(state.errorMessage);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guess Me'),
        centerTitle: true,
      ),
      body: BlocConsumer<GuessmeBloc, GuessmeState>(
        listenWhen: (previous, current) => 
            previous.status != current.status ||
            previous.errorMessage != current.errorMessage,
        listener: (context, state) {
          // Navigate to game screen when matched
          if (state.status == GuessmeStatus.inGame && state.session != null) {
            setState(() => _isSearching = false);
            context.push(
              Routes.guessmeGame,
              extra: {'sessionId': state.session!.id},
            );
          }

          // Handle queue status changes
          if (state.status == GuessmeStatus.inQueue) {
            // Still looking for a match
          } else if (state.status == GuessmeStatus.inQueueNoMatch && _isSearching) {
            // Users were found via Bluetooth but none are available for matching
            // Continue scanning to find other users or wait for them to become available
            _continueScanning();
          } else if (state.status == GuessmeStatus.ready && _isSearching) {
            // Queue left without match - stop searching
            setState(() => _isSearching = false);
          }

          // Show error messages
          if (state.status == GuessmeStatus.error && state.errorMessage != null) {
            setState(() => _isSearching = false);
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
                  // Bluetooth status banner
                  if (!_bluetoothEnabled && !_checkingBluetooth) ...[
                    _buildBluetoothBanner(context),
                    const SizedBox(height: 16),
                  ],
                  // Fade content when Bluetooth is off
                  Opacity(
                    opacity: _bluetoothEnabled ? 1.0 : 0.4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Stats card at top
                        if (state.stats != null) ...[
                          _buildStatsCard(context, state.stats!),
                          const SizedBox(height: 24),
                        ],
                        
                        // Active games section (if any)
                        if (state.session != null &&
                            (state.status == GuessmeStatus.inGame ||
                                state.status == GuessmeStatus.awaitingGuessResponse ||
                                state.status == GuessmeStatus.receivedGuessCheck)) ...[
                          _buildActiveGamesSection(context, state),
                          const SizedBox(height: 24),
                        ],

                        // Play game / searching section
                        _buildPlaySection(context, state),
                        const SizedBox(height: 24),
                        
                        // How to Play dropdown at bottom
                        _buildHowToPlayDropdown(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBluetoothBanner(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bluetooth_disabled,
                color: theme.colorScheme.error,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bluetooth is Off',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Turn on Bluetooth to discover nearby players',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _requestBluetoothOn,
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Turn On Bluetooth'),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _checkBluetoothStatus,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowToPlayDropdown(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(
            Icons.psychology,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          title: Text(
            'How to Play',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoItem(
                    context,
                    Icons.play_circle_outline,
                    'Tap "Play Game" to find a nearby player',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    context,
                    Icons.person_search,
                    'Get matched anonymously with someone nearby',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    context,
                    Icons.chat_bubble_outline,
                    'Chat for up to 1 hour without knowing who they are',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    context,
                    Icons.lightbulb_outline,
                    'Think you know who it is? Use your "Guess Check"!',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    context,
                    Icons.handshake_outlined,
                    'If you guess correctly, you can both choose to connect permanently',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    context,
                    Icons.emoji_events_outlined,
                    'Correct guesses earn you badges visible to others',
                  ),
                ],
              ),
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

  Widget _buildPlaySection(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final isInQueue = state.status == GuessmeStatus.inQueue || 
                      state.status == GuessmeStatus.inQueueNoMatch;
    final isSearchingOrInQueue = _isSearching || isInQueue;

    // Determine the status message based on current state
    String getStatusMessage(int userCount, GuessmeStatus status) {
      if (status == GuessmeStatus.inQueueNoMatch) {
        return 'Waiting for nearby players to start playing...';
      }
      if (userCount > 0) {
        return 'Found $userCount ${userCount == 1 ? 'user' : 'users'} nearby...';
      }
      return 'Looking for nearby players';
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (isSearchingOrInQueue) ...[
              // Searching state
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Searching for players...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<NearbyUsersState>(
                stream: context.read<NearbyUsersBloc>().stream,
                initialData: context.read<NearbyUsersBloc>().state,
                builder: (context, snapshot) {
                  final nearbyState = snapshot.data;
                  final userCount = nearbyState?.users.length ?? 0;
                  return Text(
                    getStatusMessage(userCount, state.status),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  _stopSearching();
                  context.read<GuessmeBloc>().add(const GuessmeLeaveQueue());
                },
                icon: const Icon(Icons.close),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ] else ...[
              // Ready to play state
              Icon(
                Icons.play_circle_filled,
                size: 80,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Ready to play?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Find a nearby player and start chatting anonymously',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _bluetoothEnabled ? _playGame : null,
                  icon: const Icon(Icons.play_arrow, size: 28),
                  label: const Text(
                    'Play Game',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
