import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../bloc/connection_bloc.dart';
import '../widgets/connection_request_card.dart';

/// Screen for viewing and managing connection requests.
class ConnectionRequestsScreen extends StatefulWidget {
  const ConnectionRequestsScreen({super.key});

  @override
  State<ConnectionRequestsScreen> createState() =>
      _ConnectionRequestsScreenState();
}

class _ConnectionRequestsScreenState extends State<ConnectionRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nearby Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
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
                      const Text('Received'),
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
                final count = state.sentRequests
                    .where((r) => r.source != 'discovery')
                    .length;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Sent'),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        _Badge(count: count, isSecondary: true),
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
            curr.errorMessage != null && prev.errorMessage != curr.errorMessage,
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
        child: TabBarView(
          controller: _tabController,
          children: const [
            _ReceivedRequestsTab(),
            _SentRequestsTab(),
          ],
        ),
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

class _ReceivedRequestsTab extends StatelessWidget {
  const _ReceivedRequestsTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        if (state.status == ConnectionBlocStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = state.receivedRequests
            .where((r) => r.source != 'discovery')
            .toList();

        if (requests.isEmpty) {
          return const _EmptyState(
            icon: Icons.inbox_outlined,
            title: 'No pending requests',
            message:
                'When someone nearby sends you a connection request,\nit will appear here.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            // Subscriptions auto-refresh, this is just for UX
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
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
            },
          ),
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
}

class _SentRequestsTab extends StatelessWidget {
  const _SentRequestsTab();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionBlocState>(
      builder: (context, state) {
        if (state.status == ConnectionBlocStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = state.sentRequests
            .where((r) => r.source != 'discovery')
            .toList();

        if (requests.isEmpty) {
          return const _EmptyState(
            icon: Icons.send_outlined,
            title: 'No pending requests',
            message:
                'Nearby requests you\'ve sent that are\nwaiting for a response will appear here.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
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
            },
          ),
        );
      },
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
