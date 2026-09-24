import 'package:flutter/material.dart';

import '../../domain/entities/help_radius.dart';

/// Widget for selecting help discovery radius.
class RadiusSelector extends StatelessWidget {
  final HelpRadius? selectedRadius;
  final ValueChanged<HelpRadius> onSelected;
  final bool enabled;

  const RadiusSelector({
    super.key,
    required this.selectedRadius,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Help Radius',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'How far should we look for helpers?',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: HelpRadius.values.map((radius) {
            final isSelected = selectedRadius == radius;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: radius == HelpRadius.values.first ? 0 : 4,
                  right: radius == HelpRadius.values.last ? 0 : 4,
                ),
                child: _RadiusChip(
                  radius: radius,
                  isSelected: isSelected,
                  enabled: enabled,
                  onTap: () => onSelected(radius),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _RadiusChip extends StatelessWidget {
  final HelpRadius radius;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _RadiusChip({
    required this.radius,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIconForRadius(radius),
                size: 24,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 4),
              Text(
                radius.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForRadius(HelpRadius radius) {
    switch (radius) {
      case HelpRadius.meters50:
        return Icons.radio_button_checked;
      case HelpRadius.meters100:
        return Icons.adjust;
      case HelpRadius.meters500:
        return Icons.circle_outlined;
      case HelpRadius.kilometers1:
        return Icons.circle;
      case HelpRadius.kilometers2:
        return Icons.album;
    }
  }
}
