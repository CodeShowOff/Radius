import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/connection_service.dart';
import '../bloc/connection_bloc.dart';

/// Dialog for sending a connection request with optional message.
class SendConnectionRequestDialog extends StatefulWidget {
  final String receiverId;
  final String? receiverDisplayName;
  final String? receiverPhotoUrl;
  final String? source;

  const SendConnectionRequestDialog({
    super.key,
    required this.receiverId,
    this.receiverDisplayName,
    this.receiverPhotoUrl,
    this.source,
  });

  /// Shows the dialog and returns true if request was sent.
  static Future<bool> show({
    required BuildContext context,
    required String receiverId,
    String? receiverDisplayName,
    String? receiverPhotoUrl,
    String? source,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SendConnectionRequestDialog(
        receiverId: receiverId,
        receiverDisplayName: receiverDisplayName,
        receiverPhotoUrl: receiverPhotoUrl,
        source: source,
      ),
    );
    return result ?? false;
  }

  @override
  State<SendConnectionRequestDialog> createState() =>
      _SendConnectionRequestDialogState();
}

class _SendConnectionRequestDialogState
    extends State<SendConnectionRequestDialog> {
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = widget.receiverDisplayName ?? 'this user';

    return AlertDialog(
      title: const Text('Send Connection Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Send a connection request to $displayName?',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Add a message (optional)',
              hintText: 'Introduce yourself...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            maxLength: 200,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _sendRequest,
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Request'),
        ),
      ],
    );
  }

  void _sendRequest() {
    // Check if request already sent
    final connectionState = context.read<ConnectionBloc>().state;
    if (connectionState.getSentRequestTo(widget.receiverId) != null ||
        connectionState.getStateForUser(widget.receiverId) == UserConnectionState.requestSent ||
        (connectionState.isActionLoading && connectionState.processingId == widget.receiverId)) {
      // Request already sent, just close the dialog
      Navigator.pop(context, false);
      return;
    }

    setState(() => _isSending = true);

    context.read<ConnectionBloc>().add(ConnectionSendRequest(
          receiverId: widget.receiverId,
          message: _messageController.text.trim().isEmpty
              ? null
              : _messageController.text.trim(),
          source: widget.source,
          receiverDisplayName: widget.receiverDisplayName,
          receiverPhotoUrl: widget.receiverPhotoUrl,
        ));

    // Close dialog after a short delay to show loading state
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context, true);
      }
    });
  }
}

/// Small badge showing pending request count.
class ConnectionRequestsBadge extends StatelessWidget {
  final Widget child;

  const ConnectionRequestsBadge({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        // Count only connection requests received from nearby
        final count = state.receivedRequests
            .where((req) => req.source == 'nearby')
            .length;

        return Badge(
          isLabelVisible: count > 0,
          label: Text(count > 9 ? '9+' : count.toString()),
          child: child,
        );
      },
    );
  }
}

/// Inline banner showing pending requests.
class PendingRequestsBanner extends StatelessWidget {
  final VoidCallback onTap;

  const PendingRequestsBanner({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        // Count only connection requests received from nearby
        final count = state.receivedRequests
            .where((req) => req.source == 'nearby')
            .length;

        if (count == 0) return const SizedBox.shrink();

        return Material(
          color: theme.colorScheme.primaryContainer,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_add,
                      size: 20,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count == 1
                              ? '1 pending request'
                              : '$count pending requests',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Tap to view and respond',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
