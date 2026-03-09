import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../bloc/connection_bloc.dart';
import '../widgets/connection_request_card.dart';

/// Combined screen showing both Nearby and Discovery requests in two sections,
/// each with Received/Sent tabs.
class AllRequestsScreen extends StatelessWidget {
  const AllRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Requests',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            tabs: [
              BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                builder: (context, state) {
                  final count = state.receivedRequests
                      .where((r) => r.source != 'discovery')
                      .length;
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Nearby'),
                        if (count > 0) ...[
                          const SizedBox(width: 8),
                          _Badge(count: count),
                        ],
                      ],
                    ),
                  );
                },
              ),
              BlocBuilder<ConnectionBloc, ConnectionBlocState>(
                builder: (context, state) {
                  final count = state.receivedRequests
                      .where((r) => r.source == 'discovery')
                      .length;
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Discovery'),
                        if (count > 0) ...[
                          const SizedBox(width: 8),
                          _Badge(count: count),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        body: BlocListener<ConnectionBloc, ConnectionBlocState>(
          listenWhen: (prev, curr) =>
              curr.errorMessage != null &&
              prev.errorMessage != curr.errorMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: const TabBarView(
            children: [
              _RequestsSection(isDiscovery: false),
              _RequestsSection(isDiscovery: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section showing Received and Sent requests for a given source type.
class _RequestsSection extends StatelessWidget {
  final bool isDiscovery;

  const _RequestsSection({required this.isDiscovery});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        if (state.status == ConnectionBlocStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final received = state.receivedRequests
            .where((r) => isDiscovery
                ? r.source == 'discovery'
                : r.source != 'discovery')
            .toList();

        final sent = state.sentRequests
            .where((r) => isDiscovery
                ? r.source == 'discovery'
                : r.source != 'discovery')
            .toList();

        if (received.isEmpty && sent.isEmpty) {
          return _EmptyState(
            icon: Icons.inbox_outlined,
            title: isDiscovery
                ? 'No discovery requests'
                : 'No nearby requests',
            message: isDiscovery
                ? 'When someone finds you by username and\nsends you a request, it will appear here.'
                : 'When someone nearby sends you a connection\nrequest, it will appear here.',
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (received.isNotEmpty) ...[
              _SectionHeader(
                title: 'Received',
                count: received.length,
              ),
              ...received.map((request) {
                final isLoading =
                    state.isActionLoading && state.processingId == request.id;
                return ConnectionRequestCard(
                  request: request,
                  isIncoming: true,
                  isLoading: isLoading,
                  onTap: () {
                    context.push(
                      Routes.userProfileWith(request.senderId),
                      extra: {
                        'displayName': request.senderDisplayName,
                        'photoUrl': request.senderPhotoUrl,
                      },
                    );
                  },
                  onAccept: () {
                    context.read<ConnectionBloc>().add(
                          ConnectionAcceptRequest(request.id),
                        );
                  },
                  onReject: () {
                    _confirmReject(context, request.id);
                  },
                );
              }),
            ],
            if (sent.isNotEmpty) ...[
              _SectionHeader(
                title: 'Sent',
                count: sent.length,
                isSecondary: true,
              ),
              ...sent.map((request) {
                final isLoading =
                    state.isActionLoading && state.processingId == request.id;
                return ConnectionRequestCard(
                  request: request,
                  isIncoming: false,
                  isLoading: isLoading,
                  onTap: () {
                    context.push(
                      Routes.userProfileWith(request.receiverId),
                      extra: {
                        'displayName': request.receiverDisplayName,
                        'photoUrl': request.receiverPhotoUrl,
                      },
                    );
                  },
                  onCancel: () {
                    _confirmCancel(context, request.id);
                  },
                );
              }),
            ],
          ],
        );
      },
    );
  }

  void _confirmReject(BuildContext context, String requestId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Decline Request?'),
        content: const Text(
          'This person will not be notified, but they won\'t be able '
          'to send another request for 24 hours.',
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
                    ConnectionRejectRequest(requestId),
                  );
            },
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, String requestId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text(
          'The request will be cancelled and the user will not be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<ConnectionBloc>().add(
                    ConnectionCancelRequest(requestId),
                  );
            },
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool isSecondary;

  const _SectionHeader({
    required this.title,
    required this.count,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          _Badge(count: count, isSecondary: isSecondary),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final bool isSecondary;

  const _Badge({
    required this.count,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSecondary
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: isSecondary
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.outline.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
