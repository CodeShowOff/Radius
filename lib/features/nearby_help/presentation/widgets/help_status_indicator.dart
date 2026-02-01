import 'package:flutter/material.dart';

import '../../domain/entities/help_request.dart';
import '../../domain/entities/help_request_status.dart';

/// Widget displaying the status of a help request.
class HelpStatusIndicator extends StatelessWidget {
  final HelpRequestStatus status;
  final bool showLabel;
  final double? iconSize;

  const HelpStatusIndicator({
    super.key,
    required this.status,
    this.showLabel = true,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getColorForStatus(status, theme);
    final icon = _getIconForStatus(status);
    final label = _getLabelForStatus(status);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: color,
            size: iconSize ?? 16,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Color _getColorForStatus(HelpRequestStatus status, ThemeData theme) {
    switch (status) {
      case HelpRequestStatus.open:
        return Colors.blue;
      case HelpRequestStatus.inProgress:
        return Colors.orange;
      case HelpRequestStatus.resolved:
        return Colors.green;
      case HelpRequestStatus.cancelled:
        return theme.colorScheme.outline;
      case HelpRequestStatus.expired:
        return theme.colorScheme.error;
    }
  }

  IconData _getIconForStatus(HelpRequestStatus status) {
    switch (status) {
      case HelpRequestStatus.open:
        return Icons.pending_outlined;
      case HelpRequestStatus.inProgress:
        return Icons.directions_walk;
      case HelpRequestStatus.resolved:
        return Icons.check_circle;
      case HelpRequestStatus.cancelled:
        return Icons.cancel_outlined;
      case HelpRequestStatus.expired:
        return Icons.timer_off;
    }
  }

  String _getLabelForStatus(HelpRequestStatus status) {
    switch (status) {
      case HelpRequestStatus.open:
        return 'Waiting for helper';
      case HelpRequestStatus.inProgress:
        return 'Helper on the way';
      case HelpRequestStatus.resolved:
        return 'Completed';
      case HelpRequestStatus.cancelled:
        return 'Cancelled';
      case HelpRequestStatus.expired:
        return 'Expired';
    }
  }
}

/// Large status badge for preview screens.
class HelpStatusBadge extends StatelessWidget {
  final HelpRequest request;

  const HelpStatusBadge({
    super.key,
    required this.request,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getColorForStatus(request.status, theme);
    final label = _getLabelForStatus(request);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForStatus(HelpRequestStatus status, ThemeData theme) {
    switch (status) {
      case HelpRequestStatus.open:
        return Colors.blue;
      case HelpRequestStatus.inProgress:
        return Colors.orange;
      case HelpRequestStatus.resolved:
        return Colors.green;
      case HelpRequestStatus.cancelled:
        return theme.colorScheme.outline;
      case HelpRequestStatus.expired:
        return theme.colorScheme.error;
    }
  }

  String _getLabelForStatus(HelpRequest request) {
    switch (request.status) {
      case HelpRequestStatus.open:
        return 'OPEN - Seeking Help';
      case HelpRequestStatus.inProgress:
        if (request.helperOnTheWay) {
          return 'Helper On The Way';
        }
        return 'Helper Assigned';
      case HelpRequestStatus.resolved:
        return 'Completed';
      case HelpRequestStatus.cancelled:
        return 'Cancelled';
      case HelpRequestStatus.expired:
        return 'Expired';
    }
  }
}
