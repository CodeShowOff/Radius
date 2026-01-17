import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../domain/entities/connection_request.dart';
import '../bloc/connection_bloc.dart';

/// A widget that listens for new connection requests and shows banner notifications.
///
/// This should be placed high in the widget tree (e.g., wrapping the main app content)
/// to ensure notifications are shown regardless of which screen the user is on.
class ConnectionRequestListener extends StatefulWidget {
  final Widget child;

  const ConnectionRequestListener({
    super.key,
    required this.child,
  });

  @override
  State<ConnectionRequestListener> createState() =>
      _ConnectionRequestListenerState();
}

class _ConnectionRequestListenerState extends State<ConnectionRequestListener> {
  List<ConnectionRequest> _previousRequests = [];
  bool _isInitialized = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<ConnectionBloc, ConnectionBlocState>(
      listenWhen: (previous, current) {
        // Listen when received requests change
        return previous.receivedRequests != current.receivedRequests;
      },
      listener: (context, state) {
        final currentRequests = state.receivedRequests;

        // Skip on first load to avoid showing notifications for existing requests
        if (!_isInitialized) {
          _previousRequests = List.from(currentRequests);
          _isInitialized = true;
          return;
        }

        // Find new requests (requests that weren't in the previous list)
        final newRequests = currentRequests.where((request) {
          return !_previousRequests.any((prev) => prev.id == request.id);
        }).toList();

        // Show notification for each new request
        for (final request in newRequests) {
          _showConnectionRequestBanner(context, request);
        }

        // Update previous requests
        _previousRequests = List.from(currentRequests);
      },
      child: widget.child,
    );
  }

  void _showConnectionRequestBanner(
      BuildContext context, ConnectionRequest request) {
    final theme = Theme.of(context);
    final senderName = request.senderDisplayName ?? 'Someone';

    // Use a MaterialBanner for a more prominent notification
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: request.senderPhotoUrl != null
              ? NetworkImage(request.senderPhotoUrl!)
              : null,
          child: request.senderPhotoUrl == null
              ? Icon(
                  Icons.person,
                  color: theme.colorScheme.onPrimaryContainer,
                )
              : null,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'New Connection Request',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$senderName wants to connect with you',
              style: theme.textTheme.bodyMedium,
            ),
            if (request.message != null && request.message!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '"${request.message}"',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              // Reject the request
              context.read<ConnectionBloc>().add(
                    ConnectionRejectRequest(request.id),
                  );
            },
            child: Text(
              'Decline',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              // Accept the request
              context.read<ConnectionBloc>().add(
                    ConnectionAcceptRequest(request.id),
                  );
              // Show success message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('You are now connected with $senderName!'),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'Message',
                    onPressed: () {
                      // Navigate to chat with the new connection
                      context.push(Routes.connectionRequests);
                    },
                  ),
                ),
              );
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    // Auto-dismiss after 10 seconds if user doesn't interact
    Future.delayed(const Duration(seconds: 10), () {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
    });
  }
}
