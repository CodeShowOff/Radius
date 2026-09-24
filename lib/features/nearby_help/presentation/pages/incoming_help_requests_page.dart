import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/routes.dart';
import '../../domain/entities/help_request.dart';
import '../bloc/nearby_help_bloc.dart';
import '../widgets/help_request_card.dart';

/// Page showing all incoming help requests from others that user can help with.
///
/// This page displays:
/// - List of open help requests from nearby users
/// - Tap to view details and accept
/// - Real-time updates as requests come in or get taken
class IncomingHelpRequestsPage extends StatefulWidget {
  /// Optional request ID to highlight/scroll to (from notification deep link).
  final String? highlightRequestId;

  const IncomingHelpRequestsPage({
    super.key,
    this.highlightRequestId,
  });

  @override
  State<IncomingHelpRequestsPage> createState() => _IncomingHelpRequestsPageState();
}

class _IncomingHelpRequestsPageState extends State<IncomingHelpRequestsPage> {
  @override
  void initState() {
    super.initState();
    // Start watching for incoming requests
    context.read<NearbyHelpBloc>().add(const NearbyHelpWatchIncomingRequests());
    
    // If we have a request ID to highlight, navigate to it after the page loads
    if (widget.highlightRequestId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToRequest(widget.highlightRequestId!);
      });
    }
  }

  @override
  void dispose() {
    // Stop watching when leaving the page
    context.read<NearbyHelpBloc>().add(const NearbyHelpStopWatchingIncomingRequests());
    super.dispose();
  }

  void _navigateToRequest(String requestId) {
    context.push(Routes.nearbyHelpRequestDetailWith(requestId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Help Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () {
              // Refresh the list
              context.read<NearbyHelpBloc>().add(const NearbyHelpWatchIncomingRequests());
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: BlocBuilder<NearbyHelpBloc, NearbyHelpState>(
        builder: (context, state) {
          if (state.status == NearbyHelpStatus.initial ||
              state.status == NearbyHelpStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.incomingRequests.isEmpty) {
            return _buildEmptyState(theme);
          }

          return _buildRequestsList(context, state.incomingRequests);
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.volunteer_activism_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Help Requests',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There are no active help requests nearby right now.\n'
              'You\'ll be notified when someone needs help.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsList(BuildContext context, List<HelpRequest> requests) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<NearbyHelpBloc>().add(const NearbyHelpWatchIncomingRequests());
        // Wait a bit for the stream to update
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: requests.length + 1, // +1 for header
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader(context, requests.length);
          }

          final request = requests[index - 1];
          final isHighlighted = request.id == widget.highlightRequestId;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: isHighlighted
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    )
                  : null,
              child: HelpRequestCard(
                request: request,
                onTap: () => _navigateToRequest(request.id),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(
            Icons.sos,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(
            '$count Help Request${count != 1 ? 's' : ''} Nearby',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
