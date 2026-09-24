import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/utils/chat_utils.dart';
import '../../data/connection_service.dart';
import '../bloc/connection_bloc.dart';

/// Button widget that adapts based on connection state.
/// Shows: Connect / Request Sent / Accept / Connected / Blocked
class ConnectionButton extends StatelessWidget {
  final String userId;
  final String? displayName;
  final String? photoUrl;
  final String? source;
  final bool compact;

  const ConnectionButton({
    super.key,
    required this.userId,
    this.displayName,
    this.photoUrl,
    this.source,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        final connectionState = state.getStateForUser(userId);
        final isLoading = state.isActionLoading && state.processingId == userId;

        // Check if there's a pending request from this user
        final receivedRequest = state.getReceivedRequestFrom(userId);
        final sentRequest = state.getSentRequestTo(userId);

        return _buildButton(
          context: context,
          state: state,
          connectionState: connectionState,
          isLoading: isLoading,
          receivedRequest: receivedRequest != null,
          sentRequest: sentRequest,
        );
      },
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required ConnectionBlocState state,
    required UserConnectionState connectionState,
    required bool isLoading,
    required bool receivedRequest,
    Object? sentRequest,
  }) {
    if (isLoading) {
      return compact
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const FilledButton(
              onPressed: null,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
    }

    // If we received a request from this user, show accept/decline
    if (receivedRequest ||
        connectionState == UserConnectionState.requestReceived) {
      return _RequestReceivedButton(
        userId: userId,
        compact: compact,
      );
    }

    return switch (connectionState) {
      UserConnectionState.notConnected => _ConnectButton(
          userId: userId,
          displayName: displayName,
          photoUrl: photoUrl,
          source: source,
          compact: compact,
        ),
      UserConnectionState.requestSent => _RequestSentButton(
          userId: userId,
          compact: compact,
        ),
      UserConnectionState.requestReceived => _RequestReceivedButton(
          userId: userId,
          compact: compact,
        ),
      UserConnectionState.connected => _ConnectedButton(
          userId: userId,
          displayName: displayName,
          compact: compact,
        ),
      UserConnectionState.blocked => _BlockedButton(
          userId: userId,
          compact: compact,
        ),
    };
  }
}

class _ConnectButton extends StatelessWidget {
  final String userId;
  final String? displayName;
  final String? photoUrl;
  final String? source;
  final bool compact;

  const _ConnectButton({
    required this.userId,
    this.displayName,
    this.photoUrl,
    this.source,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        // Prevent duplicate requests by checking current state
        final isProcessing = state.isActionLoading && state.processingId == userId;
        final alreadySent = state.getSentRequestTo(userId) != null ||
                           state.getStateForUser(userId) == UserConnectionState.requestSent;
        
        void sendRequest() {
          // Double-check before sending
          final currentState = context.read<ConnectionBloc>().state;
          if (currentState.getSentRequestTo(userId) != null ||
              currentState.getStateForUser(userId) == UserConnectionState.requestSent) {
            return; // Request already sent, do nothing
          }
          
          context.read<ConnectionBloc>().add(ConnectionSendRequest(
                receiverId: userId,
                source: source,
                receiverDisplayName: displayName,
                receiverPhotoUrl: photoUrl,
              ));
        }

        if (compact) {
          return IconButton.filled(
            onPressed: (isProcessing || alreadySent) ? null : sendRequest,
            icon: isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add),
            tooltip: alreadySent ? 'Request Sent' : 'Connect',
          );
        }

        return FilledButton.icon(
          onPressed: (isProcessing || alreadySent) ? null : sendRequest,
          icon: isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add, size: 18),
          label: Text(alreadySent ? 'Request Sent' : 'Connect'),
        );
      },
    );
  }
}

class _RequestSentButton extends StatelessWidget {
  final String userId;
  final bool compact;

  const _RequestSentButton({
    required this.userId,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    void showOptions() {
      showModalBottomSheet(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancel Request'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  // Find the request ID
                  final state = context.read<ConnectionBloc>().state;
                  final request = state.getSentRequestTo(userId);
                  if (request != null) {
                    context.read<ConnectionBloc>().add(
                          ConnectionCancelRequest(request.id),
                        );
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (compact) {
      return IconButton(
        onPressed: showOptions,
        icon: Icon(
          Icons.schedule,
          color: theme.colorScheme.outline,
        ),
        tooltip: 'Request Sent',
      );
    }

    return OutlinedButton.icon(
      onPressed: showOptions,
      icon: Icon(
        Icons.schedule,
        size: 18,
        color: theme.colorScheme.outline,
      ),
      label: Text(
        'Pending',
        style: TextStyle(color: theme.colorScheme.outline),
      ),
    );
  }
}

class _RequestReceivedButton extends StatelessWidget {
  final String userId;
  final bool compact;

  const _RequestReceivedButton({
    required this.userId,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    void acceptRequest() {
      final state = context.read<ConnectionBloc>().state;
      final request = state.getReceivedRequestFrom(userId);
      if (request != null) {
        context.read<ConnectionBloc>().add(
              ConnectionAcceptRequest(request.id),
            );
      }
    }

    void rejectRequest() {
      final state = context.read<ConnectionBloc>().state;
      final request = state.getReceivedRequestFrom(userId);
      if (request != null) {
        context.read<ConnectionBloc>().add(
              ConnectionRejectRequest(request.id),
            );
      }
    }

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: rejectRequest,
            icon: const Icon(Icons.close),
            tooltip: 'Decline',
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          IconButton.filled(
            onPressed: acceptRequest,
            icon: const Icon(Icons.check),
            tooltip: 'Accept',
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: rejectRequest,
          child: const Text('Decline'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: acceptRequest,
          child: const Text('Accept'),
        ),
      ],
    );
  }
}

class _ConnectedButton extends StatelessWidget {
  final String userId;
  final String? displayName;
  final bool compact;

  const _ConnectedButton({
    required this.userId,
    this.displayName,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    void showOptions() {
      showModalBottomSheet(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.message_outlined),
                title: const Text('Message'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final authState = context.read<AuthBloc>().state;
                  if (authState is AuthAuthenticated) {
                    final currentUserId = authState.user.id;
                    final conversationId = ChatUtils.getDirectMessageChannelId(
                      currentUserId,
                      userId,
                    );
                    context.go(Routes.chatWith(conversationId));
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Remove Connection',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmRemove(context);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.block,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Block User',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmBlock(context);
                },
              ),
            ],
          ),
        ),
      );
    }

    if (compact) {
      return IconButton(
        onPressed: showOptions,
        icon: Icon(
          Icons.check_circle,
          color: theme.colorScheme.primary,
        ),
        tooltip: 'Connected',
      );
    }

    return FilledButton.tonalIcon(
      onPressed: showOptions,
      icon: Icon(
        Icons.check_circle,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      label: const Text('Connected'),
    );
  }

  void _confirmRemove(BuildContext context) {
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
              final state = context.read<ConnectionBloc>().state;
              final connection = state.getConnectionWith(userId);
              if (connection != null) {
                context.read<ConnectionBloc>().add(
                      ConnectionRemove(connection.id),
                    );
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _confirmBlock(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block User?'),
        content: const Text(
          'This user will not be able to send you connection requests '
          'or see you in nearby users. You can unblock them later.',
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
                    ConnectionBlockUser(userId, blockedName: displayName),
                  );
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}

class _BlockedButton extends StatelessWidget {
  final String userId;
  final bool compact;

  const _BlockedButton({
    required this.userId,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    void unblock() {
      context.read<ConnectionBloc>().add(ConnectionUnblockUser(userId));
    }

    if (compact) {
      return IconButton(
        onPressed: unblock,
        icon: Icon(
          Icons.block,
          color: theme.colorScheme.error,
        ),
        tooltip: 'Blocked - Tap to unblock',
      );
    }

    return OutlinedButton.icon(
      onPressed: unblock,
      icon: Icon(
        Icons.block,
        size: 18,
        color: theme.colorScheme.error,
      ),
      label: Text(
        'Blocked',
        style: TextStyle(color: theme.colorScheme.error),
      ),
    );
  }
}
