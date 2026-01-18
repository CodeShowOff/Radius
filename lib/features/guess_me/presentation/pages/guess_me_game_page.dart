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
class GuessmeGamePage extends StatefulWidget {
  final String sessionId;

  const GuessmeGamePage({
    super.key,
    required this.sessionId,
  });

  @override
  State<GuessmeGamePage> createState() => _GuessmeGamePageState();
}

class _GuessmeGamePageState extends State<GuessmeGamePage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  Timer? _countdownTimer;
  Duration _timeRemaining = const Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    final state = context.read<GuessmeBloc>().state;
    if (state.session != null) {
      final endTime = state.session!.expiresAt;
      final now = DateTime.now();
      if (endTime != null && endTime.isAfter(now)) {
        _timeRemaining = endTime.difference(now);
      } else {
        _timeRemaining = Duration.zero;
      }
    }

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

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
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

  void _showGuessCheckReceived() {
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
              context
                  .read<GuessmeBloc>()
                  .add(const GuessmeRespondToGuessCheck(false));
            },
            child: const Text('No, Wrong!'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
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

  void _leaveGame({bool findNewMatch = false}) {
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
              if (findNewMatch) {
                // Pop back to lobby, which will allow user to join queue again
                context.pop();
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
          if (!findNewMatch)
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.read<GuessmeBloc>().add(const GuessmeLeaveGame());
                // User can immediately find a new match from lobby
                context.pop();
              },
              child: const Text('Find New Match'),
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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GuessmeBloc, GuessmeState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        // Show guess check dialog when received
        if (state.status == GuessmeStatus.receivedGuessCheck) {
          _showGuessCheckReceived();
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
                // Messages
                Expanded(
                  child: _buildMessagesList(context, state),
                ),

                // Guess check button (if not used)
                if (state.isInGame && !state.hasUsedGuess)
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

  PreferredSizeWidget _buildAppBar(BuildContext context, GuessmeState state) {
    final theme = Theme.of(context);
    final isLowTime = _timeRemaining.inMinutes < 5;

    // Get the other player's name from session
    String otherPlayerName = 'Mystery User';
    if (state.session != null && state.currentUserId != null) {
      otherPlayerName =
          state.session!.getOtherPlayerName(state.currentUserId!) ??
              'Mystery User';
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _leaveGame,
      ),
      title: Column(
        children: [
          Text(
            otherPlayerName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
        if (state.isInGame)
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') {
                _leaveGame();
              } else if (value == 'find_new') {
                _leaveGame(findNewMatch: true);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'find_new',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Find New Match'),
                  ],
                ),
              ),
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
                Text(
                  message.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
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
            // Show initial instead of avatar (no profile picture)
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
          Flexible(
            child: Container(
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
                style: TextStyle(
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
              decoration: InputDecoration(
                hintText: 'Type a message...',
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
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }

  void _showGameEndedDialog(GuessmeState state) {
    final session = state.session;
    final wasSuccessfulGuess =
        session?.status == GuessmeSessionStatus.completed;
    final otherPlayerId = state.otherPlayerId;
    final otherPlayerName =
        state.session?.getOtherPlayerName(state.currentUserId ?? '') ??
            'this user';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              wasSuccessfulGuess ? Icons.celebration : Icons.timer_off,
              color: wasSuccessfulGuess ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                wasSuccessfulGuess ? 'Correct Guess!' : 'Time\'s Up!',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (wasSuccessfulGuess) ...[
              Text('You were chatting with: $otherPlayerName'),
              const SizedBox(height: 16),
              const Text(
                'Would you like to connect with them?',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ] else ...[
              const Text('The game has ended.'),
              const SizedBox(height: 8),
              Text('You were chatting with: $otherPlayerName'),
              const SizedBox(height: 8),
              const Text('Maybe next time you\'ll figure it out faster!'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.pop();
            },
            child: Text(wasSuccessfulGuess ? 'No Thanks' : 'Back to Lobby'),
          ),
          if (wasSuccessfulGuess && otherPlayerId != null)
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _sendConnectionRequest(
                  otherPlayerId,
                  otherPlayerName,
                  state.currentUserId!,
                );
                if (mounted) {
                  context.pop();
                }
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Connect'),
            ),
          if (!wasSuccessfulGuess)
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                context.pop();
              },
              child: const Text('Find New Match'),
            ),
        ],
      ),
    );
  }

  Future<void> _sendConnectionRequest(
    String otherUserId,
    String otherUserName,
    String currentUserId,
  ) async {
    try {
      final connectionService = getIt<ConnectionService>();
      final result = await connectionService.sendRequest(
        senderId: currentUserId,
        receiverId: otherUserId,
        source: 'guessme',
      );
      if (mounted) {
        switch (result) {
          case ConnectionSuccess():
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connection request sent to $otherUserName!'),
                backgroundColor: Colors.green,
              ),
            );
          case ConnectionFailure(:final message):
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to send request: $message'),
                backgroundColor: Colors.red,
              ),
            );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send request: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
