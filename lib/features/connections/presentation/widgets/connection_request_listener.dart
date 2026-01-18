import 'dart:collection';

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

class _ConnectionRequestListenerState extends State<ConnectionRequestListener>
  with TickerProviderStateMixin {
  List<ConnectionRequest> _previousRequests = [];
  bool _isInitialized = false;

  final Queue<ConnectionRequest> _queue = Queue<ConnectionRequest>();
  OverlayEntry? _activeEntry;
  AnimationController? _controller;

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
          _enqueueBanner(request);
        }

        // Update previous requests
        _previousRequests = List.from(currentRequests);
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _removeActiveEntry();
    super.dispose();
  }

  void _enqueueBanner(ConnectionRequest request) {
    _queue.addLast(request);
    _showNextIfIdle();
  }

  void _showNextIfIdle() {
    if (!mounted) return;
    if (_activeEntry != null) return;
    if (_queue.isEmpty) return;

    final request = _queue.removeFirst();
    _showConnectionRequestOverlay(request);
  }

  void _removeActiveEntry() {
    _controller?.dispose();
    _controller = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  void _showConnectionRequestOverlay(ConnectionRequest request) {
    final overlay = Overlay.of(context, rootOverlay: true);

    final theme = Theme.of(context);
    final senderName = request.senderDisplayName ?? 'Someone';

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 180),
    );

    final animation = CurvedAnimation(
      parent: _controller!,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _activeEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            top: true,
            bottom: false,
            child: Material(
              color: Colors.transparent,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1.1),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(
                  opacity: animation,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            _dismissActive();
                            context.push(Routes.connectionRequests);
                          },
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                backgroundImage: request.senderPhotoUrl !=
                                            null &&
                                        request.senderPhotoUrl!.isNotEmpty
                                    ? NetworkImage(request.senderPhotoUrl!)
                                    : null,
                                child: (request.senderPhotoUrl == null ||
                                        request.senderPhotoUrl!.isEmpty)
                                    ? Icon(
                                        Icons.person,
                                        color: theme
                                            .colorScheme.onPrimaryContainer,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Connection request',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$senderName wants to connect',
                                      style: theme.textTheme.bodyMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (request.message != null &&
                                        request.message!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '"${request.message!.trim()}"',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () {
                                  _dismissActive();
                                  context
                                      .read<ConnectionBloc>()
                                      .add(ConnectionRejectRequest(request.id));
                                },
                                child: Text(
                                  'Decline',
                                  style:
                                      TextStyle(color: theme.colorScheme.error),
                                ),
                              ),
                              const SizedBox(width: 6),
                              FilledButton(
                                onPressed: () {
                                  _dismissActive();
                                  context
                                      .read<ConnectionBloc>()
                                      .add(ConnectionAcceptRequest(request.id));
                                },
                                child: const Text('Accept'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_activeEntry!);
    _controller!.forward();

    // Auto-dismiss after a short time (like WhatsApp), but only if still showing.
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (_activeEntry == null) return;
      _dismissActive();
    });
  }

  Future<void> _dismissActive() async {
    final controller = _controller;
    if (controller == null) {
      _removeActiveEntry();
      _showNextIfIdle();
      return;
    }

    try {
      if (controller.isAnimating || controller.value > 0) {
        await controller.reverse();
      }
    } finally {
      _removeActiveEntry();
      _showNextIfIdle();
    }
  }
}
