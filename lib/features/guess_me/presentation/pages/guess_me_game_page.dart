import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/router/routes.dart';
import '../../../chat/data/adapters/guessme_message_adapter.dart';
import '../../../chat/domain/entities/chat_config.dart';
import '../../../chat/presentation/widgets/shared_chat_input.dart';
import '../../../chat/presentation/widgets/shared_messages_list.dart';
import '../../../connections/data/connection_service.dart';
import '../../domain/entities/guess_me_session.dart';
import '../bloc/guess_me_bloc.dart';

/// The game chat screen for GuessMe.
/// Anonymous chat with timer and guess functionality.
/// 
/// Flow:
/// 1. Active game -> chat and guess check available
/// 2. Guess check initiated -> waiting for response
/// 3. Correct guess -> Connection prompt shown to BOTH users
/// 4. Both respond -> Show result and end game
/// 5. If both agree -> Convert to permanent connection and redirect to Connections chat
class GuessMeGamePage extends StatefulWidget {
  final String sessionId;

  const GuessMeGamePage({
    super.key,
    required this.sessionId,
  });

  @override
  State<GuessMeGamePage> createState() => _GuessMeGamePageState();
}

class _GuessMeGamePageState extends State<GuessMeGamePage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final Logger _logger = Logger();

  Timer? _countdownTimer;
  Duration _timeRemaining = const Duration(hours: 1);
  bool _connectionPromptShown = false;
  bool _guessCheckDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // CRITICAL: Ensure the BLoC is subscribed to this session's messages
    // This MUST happen immediately to guarantee message streaming works
    // Three scenarios where this is needed:
    // 1. User opens game page via deep link (no lobby navigation)
    // 2. User refreshes the page while in a game
    // 3. Race condition where session created but stream not yet established
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _logger.i('Game page loaded - ensuring session subscription for: ${widget.sessionId}');
        context.read<GuessmeBloc>().add(
          GuessmeEnsureSessionSubscription(widget.sessionId),
        );
      }
    });
    
    _startCountdown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App went to background - Firestore streams will pause automatically
    } else if (state == AppLifecycleState.resumed) {
      // Refresh timer
      _refreshTimer();
      
      // Re-ensure subscription is active after app resume
      // This handles cases where the stream may have been interrupted
      context.read<GuessmeBloc>().add(
        GuessmeEnsureSessionSubscription(widget.sessionId),
      );
    }
  }

  void _startCountdown() {
    final state = context.read<GuessmeBloc>().state;
    _refreshTimerFromState(state);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_timeRemaining.inSeconds > 0) {
            _timeRemaining = _timeRemaining - const Duration(seconds: 1);
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  void _refreshTimer() {
    final state = context.read<GuessmeBloc>().state;
    _refreshTimerFromState(state);
  }

  void _refreshTimerFromState(GuessmeState state) {
    if (state.session != null) {
      final endTime = state.session!.expiresAt;
      final now = DateTime.now();
      if (endTime != null && endTime.isAfter(now)) {
        _timeRemaining = endTime.difference(now);
      } else {
        _timeRemaining = Duration.zero;
      }
    }
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;

    context.read<GuessmeBloc>().add(GuessmeSendMessage(text));

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0, // Reverse list, 0 is bottom
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _initiateGuessCheck() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Guess Check'),
        content: const Text(
          'You\'re about to check if you know who this person is.\n\n'
          'They will confirm if your guess is correct.\n\n'
          'You can only use this ONCE per game!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context
                  .read<GuessmeBloc>()
                  .add(const GuessmeInitiateGuessCheck());
            },
            child: const Text('Use Guess Check'),
          ),
        ],
      ),
    );
  }

  void _showGuessCheckReceivedDialog() {
    if (_guessCheckDialogShown) {
      debugPrint('GuessMe: Guess check dialog already shown, skipping');
      return;
    }
    _guessCheckDialogShown = true;
    debugPrint('GuessMe: Showing guess check dialog');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.orange),
            SizedBox(width: 8),
            Text('Guess Check!'),
          ],
        ),
        content: const Text(
          'Your partner thinks they know who you are!\n\n'
          'Do they know you in real life?',
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _guessCheckDialogShown = false;
              context
                  .read<GuessmeBloc>()
                  .add(const GuessmeRespondToGuessCheck(false));
            },
            child: const Text('No, Wrong!'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _guessCheckDialogShown = false;
              context
                  .read<GuessmeBloc>()
                  .add(const GuessmeRespondToGuessCheck(true));
            },
            child: const Text('Yes, Correct!'),
          ),
        ],
      ),
    );
  }

  void _showConnectionPromptDialog(GuessmeState state) {
    if (_connectionPromptShown) return;
    if (state.hasRespondedToConnectionPrompt) return;
    _connectionPromptShown = true;

    final otherPlayerId = state.otherPlayerId;

    // Fetch the other player's profile
    _fetchOtherPlayerProfile(otherPlayerId).then((profile) {
      if (!mounted) return;

      final otherPlayerName = profile?['name'] as String? ?? 'this user';
      final otherPlayerPhoto = profile?['photoUrl'] as String?;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.celebration, color: Colors.green),
              SizedBox(width: 8),
              Text('Correct Guess!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show the other player's profile
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: otherPlayerPhoto != null
                        ? NetworkImage(otherPlayerPhoto)
                        : null,
                    child: otherPlayerPhoto == null
                        ? Text(
                            otherPlayerName.isNotEmpty
                                ? otherPlayerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'You were chatting with:',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          otherPlayerName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Would you like to connect and continue chatting permanently?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                'Both players must agree to connect.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context
                    .read<GuessmeBloc>()
                    .add(const GuessmeRespondToConnectionPrompt(false));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('No Thanks'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                context
                    .read<GuessmeBloc>()
                    .add(const GuessmeRespondToConnectionPrompt(true));
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Connect'),
            ),
          ],
        ),
      );
    });
  }

  void _showGameEndedDialog(GuessmeState state) {
    final session = state.session;
    if (session == null) {
      context.pop();
      return;
    }

    final mutualSuccess = session.mutualConnectionSuccess ?? false;
    final wasExpired = session.status == GuessmeSessionStatus.expired;
    final wasCancelled = session.status == GuessmeSessionStatus.cancelled;
    final otherPlayerId = state.otherPlayerId;

    _fetchOtherPlayerProfile(otherPlayerId).then((profile) {
      if (!mounted) return;

      final otherPlayerName = profile?['name'] as String? ?? 'Unknown';
      final otherPlayerPhoto = profile?['photoUrl'] as String?;

      String title;
      IconData icon;
      Color iconColor;
      String message;
      String? actionLabel;
      VoidCallback? onAction;

      if (mutualSuccess) {
        title = 'Connected!';
        icon = Icons.celebration;
        iconColor = Colors.green;
        message = 'You and $otherPlayerName are now connected! You can continue chatting in your connections.';
        actionLabel = 'Go to Chat';
        onAction = () {
          Navigator.pop(context); // Close dialog
          context.pop(); // Close game page
          
          // Navigate to the new permanent chat
          if (state.convertedConversationId != null && otherPlayerId != null) {
            context.push(
              Routes.chatWith(state.convertedConversationId!),
              extra: {
                'currentUserId': state.currentUserId,
                'otherUserId': otherPlayerId,
                'otherUserName': otherPlayerName,
                'otherUserPhotoUrl': otherPlayerPhoto,
              },
            );
          }
        };
      } else if (wasExpired) {
        title = 'Time\'s Up!';
        icon = Icons.timer_off;
        iconColor = Colors.orange;
        message = 'You were chatting with $otherPlayerName. Better luck next time!';
      } else if (wasCancelled) {
        title = 'Game Ended';
        icon = Icons.exit_to_app;
        iconColor = Colors.grey;
        message = 'The game has ended. You were chatting with $otherPlayerName.';
      } else {
        // Connection was declined
        title = 'Maybe Next Time';
        icon = Icons.sentiment_neutral;
        iconColor = Colors.blue;
        message = 'The connection was not made. You were chatting with $otherPlayerName.';
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: otherPlayerPhoto != null
                    ? NetworkImage(otherPlayerPhoto)
                    : null,
                child: otherPlayerPhoto == null
                    ? Text(
                        otherPlayerName.isNotEmpty
                            ? otherPlayerName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            if (actionLabel != null && onAction != null)
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel),
              )
            else
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  context.pop();
                },
                child: const Text('Back to Lobby'),
              ),
          ],
        ),
      );
    });
  }

  void _leaveGame() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave Game'),
        content: const Text(
          'Are you sure you want to leave?\n\n'
          'This will end the game for both players.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<GuessmeBloc>().add(const GuessmeLeaveGame());
              context.pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>?> _fetchOtherPlayerProfile(String? userId) async {
    if (userId == null) return null;
    try {
      final connectionService = getIt<ConnectionService>();
      return await connectionService.getUserProfile(userId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GuessmeBloc, GuessmeState>(
      listenWhen: (previous, current) {
        // Log state changes for debugging
        if (previous.status != current.status) {
          debugPrint('GuessMe: Status changed from ${previous.status} to ${current.status}');
        }
        if (previous.session?.guessCheckPending != current.session?.guessCheckPending) {
          debugPrint('GuessMe: guessCheckPending changed from ${previous.session?.guessCheckPending} to ${current.session?.guessCheckPending}');
          debugPrint('GuessMe: guessCheckInitiator: ${current.session?.guessCheckInitiator}');
        }
        
        // Trigger listener when:
        // 1. Status changes (including to receivedGuessCheck)
        // 2. Expiry time changes
        // 3. Connection confirmations status changes
        // 4. Guess check pending changes (CRITICAL for receiving guess check)
        return previous.status != current.status ||
            previous.session?.expiresAt != current.session?.expiresAt ||
            previous.session?.awaitingConnectionConfirmations != current.session?.awaitingConnectionConfirmations ||
            previous.session?.guessCheckPending != current.session?.guessCheckPending;
      },
      listener: (context, state) {
        // Update countdown timer if expiry time changed
        if (state.session?.expiresAt != null) {
          _refreshTimerFromState(state);
        }

        // Show guess check dialog when received
        if (state.status == GuessmeStatus.receivedGuessCheck) {
          debugPrint('GuessMe: Status is receivedGuessCheck - Dialog shown flag: $_guessCheckDialogShown');
          debugPrint('GuessMe: Session guessCheckPending: ${state.session?.guessCheckPending}');
          debugPrint('GuessMe: Session guessCheckInitiator: ${state.session?.guessCheckInitiator}');
          _showGuessCheckReceivedDialog();
        }

        // Show connection prompt when awaiting confirmation
        if (state.status == GuessmeStatus.awaitingConnectionConfirmation &&
            !state.hasRespondedToConnectionPrompt) {
          _showConnectionPromptDialog(state);
        }

        // Handle game ended
        if (state.status == GuessmeStatus.gameEnded) {
          _showGameEndedDialog(state);
        }
      },
      builder: (context, state) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _leaveGame();
            }
          },
          child: Scaffold(
            appBar: _buildAppBar(context, state),
            body: Column(
              children: [
                // Connection confirmation banner
                if (state.status == GuessmeStatus.awaitingConnectionConfirmation)
                  _buildConnectionConfirmationBanner(context, state),

                // Messages
                Expanded(
                  child: _buildMessagesList(context, state),
                ),

                // Input
                _buildMessageInput(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionConfirmationBanner(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final hasResponded = state.hasRespondedToConnectionPrompt;
    final response = state.connectionPromptResponse;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.green.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            hasResponded ? Icons.check_circle : Icons.hourglass_top,
            color: Colors.green,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasResponded
                  ? (response == true
                      ? 'You want to connect! Waiting for the other player...'
                      : 'You declined. Waiting for the other player...')
                  : 'Correct guess! Decide if you want to connect.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final isLowTime = _timeRemaining.inMinutes < 5;

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _leaveGame,
      ),
      title: Column(
        children: [
          const Text(
            'Mystery Player',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          Text(
            _formatDuration(_timeRemaining),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isLowTime ? Colors.red : theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        // Guess Check button - shows when available
        if (state.isInGame && 
            !state.hasUsedGuess && 
            state.status != GuessmeStatus.awaitingConnectionConfirmation)
          if (state.status == GuessmeStatus.awaitingGuessResponse)
            // Waiting for response state
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange,
                    ),
                  ),
                ),
              ),
            )
          else
            // Available to use
            IconButton(
              icon: const Icon(Icons.psychology),
              color: Colors.orange,
              tooltip: 'Guess Check',
              onPressed: _initiateGuessCheck,
            ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'leave') {
              _leaveGame();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'leave',
              child: Row(
                children: [
                  Icon(Icons.exit_to_app, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Leave Game', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessagesList(BuildContext context, GuessmeState state) {
    // Convert GuessMe messages to standard Message format for shared component
    final messages = GuessmeMessageAdapter.toMessages(state.messages);

    // Create config for anonymous GuessMe chat
    final config = ChatConfig.guessMe(
      expiresAt: state.session?.expiresAt,
    );

    return SharedMessagesList(
      messages: messages,
      currentUserId: state.currentUserId ?? '',
      config: config,
      scrollController: _scrollController,
      isLoading: false,
      onRetryMessage: (message) {
        context.read<GuessmeBloc>().add(
          GuessmeRetryMessage(localMessageId: message.id, text: message.text),
        );
      },
      onRemoveFailedMessage: (message) {
        context.read<GuessmeBloc>().add(
          GuessmeRemoveFailedMessage(message.id),
        );
      },
    );
  }

  Widget _buildMessageInput(BuildContext context, GuessmeState state) {
    final canSend = state.isInGame && state.status != GuessmeStatus.gameEnded;

    // Create config for anonymous GuessMe chat
    final config = ChatConfig.guessMe(
      expiresAt: state.session?.expiresAt,
    );

    return SharedChatInput(
      config: config,
      onSend: _sendMessage,
      enabled: canSend,
      disabledMessage: canSend ? null : 'Game ended',
    );
  }
}
