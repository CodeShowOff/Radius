import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/connection_request.dart';

/// Card widget for displaying a connection request.
class ConnectionRequestCard extends StatelessWidget {
  final ConnectionRequest request;
  final bool isIncoming;
  final bool isLoading;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  const ConnectionRequestCard({
    super.key,
    required this.request,
    required this.isIncoming,
    this.isLoading = false,
    this.onAccept,
    this.onReject,
    this.onCancel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = isIncoming
        ? request.senderDisplayName ?? 'Unknown User'
        : request.receiverDisplayName ?? 'Unknown User';
    final photoUrl =
        isIncoming ? request.senderPhotoUrl : request.receiverPhotoUrl;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              _Avatar(
                photoUrl: photoUrl,
                displayName: displayName,
              ),
              const SizedBox(width: 12),

              // User info and message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _TimeAgo(dateTime: request.sentAt),
                      ],
                    ),
                    if (request.message != null &&
                        request.message!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        request.message!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (request.source != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _getSourceIcon(request.source!),
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getSourceLabel(request.source!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Action buttons
                    if (isLoading)
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (isIncoming)
                      _IncomingActions(
                        onAccept: onAccept,
                        onReject: onReject,
                      )
                    else
                      _OutgoingActions(
                        onCancel: onCancel,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    return switch (source) {
      'nearby' => Icons.radar,
      'search' => Icons.search,
      'profile' => Icons.person,
      _ => Icons.link,
    };
  }

  String _getSourceLabel(String source) {
    return switch (source) {
      'nearby' => 'Met nearby',
      'search' => 'From search',
      'profile' => 'From profile',
      _ => 'Connection request',
    };
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String displayName;

  const _Avatar({
    this.photoUrl,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CircleAvatar(
      radius: 28,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: photoUrl != null
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initials(theme),
                errorWidget: (_, __, ___) => _initials(theme),
              ),
            )
          : _initials(theme),
    );
  }

  Widget _initials(ThemeData theme) {
    return Text(
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _TimeAgo extends StatelessWidget {
  final DateTime dateTime;

  const _TimeAgo({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    String text;
    if (difference.inMinutes < 1) {
      text = 'Just now';
    } else if (difference.inHours < 1) {
      text = '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      text = '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      text = '${difference.inDays}d ago';
    } else {
      text = '${(difference.inDays / 7).floor()}w ago';
    }

    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

class _IncomingActions extends StatelessWidget {
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _IncomingActions({
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onReject,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: onAccept,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Accept'),
          ),
        ),
      ],
    );
  }
}

class _OutgoingActions extends StatelessWidget {
  final VoidCallback? onCancel;

  const _OutgoingActions({this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Cancel Request'),
          ),
        ),
      ],
    );
  }
}

/// Expiration indicator for requests.
class RequestExpirationBanner extends StatelessWidget {
  final ConnectionRequest request;

  const RequestExpirationBanner({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLeft = request.timeUntilExpiration;

    if (timeLeft.isNegative) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Expired',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      );
    }

    String text;
    Color? bgColor;

    if (timeLeft.inDays > 3) {
      return const SizedBox.shrink();
    } else if (timeLeft.inDays >= 1) {
      text = 'Expires in ${timeLeft.inDays}d';
      bgColor = theme.colorScheme.tertiaryContainer;
    } else if (timeLeft.inHours >= 1) {
      text = 'Expires in ${timeLeft.inHours}h';
      bgColor = theme.colorScheme.errorContainer.withOpacity(0.5);
    } else {
      text = 'Expires soon';
      bgColor = theme.colorScheme.errorContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
