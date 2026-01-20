import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection.dart';
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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  Timer? _countdownTimer;
  Duration _timeRemaining = const Duration(hours: 1);
  bool _connectionPromptShown = false;
  bool _guessCheckDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCountdown();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App went to background - the BLoC will handle cleanup if needed
    } else if (state == AppLifecycleState.resumed) {
      // Refresh timer
      _refreshTimer();
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

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    context.read<GuessmeBloc>().add(GuessmeSendMessage(text));
    _messageController.clear();
    _focusNode.requestFocus();

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
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
    if (_guessCheckDialogShown) return;
    _guessCheckDialogShown = true;

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

      if (mutualSuccess) {
        title = 'Connected!';
        icon = Icons.celebration;
        iconColor = Colors.green;
        message = 'You and $otherPlayerName are now connected! You can continue chatting in your connections.';
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
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.session?.expiresAt != current.session?.expiresAt ||
          previous.session?.awaitingConnectionConfirmations != current.session?.awaitingConnectionConfirmations,
      listener: (context, state) {
        // Update countdown timer if expiry time changed
        if (state.session?.expiresAt != null) {
          _refreshTimerFromState(state);
        }

        // Show guess check dialog when received
        if (state.status == GuessmeStatus.receivedGuessCheck) {
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

                // Guess check button (if not used and not in connection phase)
                if (state.isInGame && 
                    !state.hasUsedGuess && 
                    state.status != GuessmeStatus.awaitingConnectionConfirmation)
                  _buildGuessCheckBar(context, state),

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
    final theme = Theme.of(context);
    final messages = state.messages;

    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Start chatting!',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Say hi to your mystery partner.\nTry to figure out who they are!',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMe = message.senderId == state.currentUserId;

        return _buildMessageBubble(context, message, isMe);
      },
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    GuessmeMessage message,
    bool isMe,
  ) {
    final theme = Theme.of(context);

    // System messages
    if (message.type == GuessmeMessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    // Guess check messages
    if (message.type == GuessmeMessageType.guessCheck) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message.text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Regular messages
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondary,
              child: const Text(
                '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IntrinsicWidth(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Text(
                message.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isMe
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildGuessCheckBar(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);

    if (state.status == GuessmeStatus.awaitingGuessResponse) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.orange.withValues(alpha: 0.1),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Waiting for response...'),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Think you know who this is?',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: _initiateGuessCheck,
            icon: const Icon(Icons.psychology, size: 18),
            label: const Text('Guess Check'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final canSend = state.isInGame && state.status != GuessmeStatus.gameEnded;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              enabled: canSend,
              decoration: InputDecoration(
                hintText: canSend ? 'Type a message...' : 'Game ended',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: canSend ? (_) => _sendMessage() : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: canSend ? _sendMessage : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
