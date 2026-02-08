import 'package:flutter/material.dart';

import 'cached_avatar.dart';

/// A request item for the pending requests sheet.
/// Abstracts over different join request types from random/location groups.
class PendingRequestItem {
  final String id;
  final String userId;
  final String displayName;
  final String? username;
  final String? photoUrl;
  final String? message;
  final DateTime requestedAt;

  const PendingRequestItem({
    required this.id,
    required this.userId,
    required this.displayName,
    this.username,
    this.photoUrl,
    this.message,
    required this.requestedAt,
  });
}

/// A reusable bottom sheet for showing and managing pending join requests.
///
/// Used by both random group and location group chat pages.
/// Supports:
/// - List of pending requests with approve/reject
/// - "Accept All" button to bulk-approve
class PendingRequestsSheet extends StatelessWidget {
  final List<PendingRequestItem> requests;
  final void Function(PendingRequestItem request) onApprove;
  final void Function(PendingRequestItem request) onReject;
  final VoidCallback onAcceptAll;

  const PendingRequestsSheet({
    super.key,
    required this.requests,
    required this.onApprove,
    required this.onReject,
    required this.onAcceptAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header with title and Accept All
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.person_add,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pending Requests',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (requests.isNotEmpty)
                    FilledButton.tonal(
                      onPressed: () {
                        _confirmAcceptAll(context);
                      },
                      child: const Text('Accept All'),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content
            Expanded(
              child: requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No pending requests',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All join requests have been handled',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final request = requests[index];
                        return _RequestTile(
                          request: request,
                          onApprove: () => onApprove(request),
                          onReject: () => onReject(request),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _confirmAcceptAll(BuildContext context) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Accept All Requests'),
        content: Text(
          'Are you sure you want to approve all ${requests.length} pending request${requests.length == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onAcceptAll();
            },
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
            ),
            child: const Text('Accept All'),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final PendingRequestItem request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CachedAvatar(
              imageUrl: request.photoUrl,
              name: request.displayName,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (request.username != null)
                    Text(
                      '@${request.username}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (request.message != null &&
                      request.message!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      request.message!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close),
              color: theme.colorScheme.error,
              onPressed: onReject,
              tooltip: 'Reject',
            ),
            IconButton(
              icon: const Icon(Icons.check),
              color: theme.colorScheme.primary,
              onPressed: onApprove,
              tooltip: 'Approve',
            ),
          ],
        ),
      ),
    );
  }
}
