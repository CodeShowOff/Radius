import 'package:flutter/material.dart';

import '../../domain/entities/user_location.dart';

/// Card for displaying and managing a saved location.
class LocationCard extends StatelessWidget {
  final UserLocation? location;
  final LocationType type;
  final VoidCallback onSetLocation;
  final VoidCallback? onRemove;
  final VoidCallback? onToggleActive;

  const LocationCard({
    super.key,
    this.location,
    required this.type,
    required this.onSetLocation,
    this.onRemove,
    this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLocation = location != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasLocation ? null : onSetLocation,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getColorForType(type, theme).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getIconForType(type),
                      color: _getColorForType(type, theme),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type.displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hasLocation && location!.address != null)
                          Text(
                            location!.address!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        else if (!hasLocation)
                          Text(
                            'Tap to set location',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasLocation) ...[
                    // Active toggle
                    Switch(
                      value: location!.isActive,
                      onChanged: onToggleActive != null
                          ? (_) => onToggleActive!()
                          : null,
                    ),
                  ] else
                    Icon(
                      Icons.add_location_alt_outlined,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              if (hasLocation) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSetLocation,
                        icon: const Icon(Icons.edit_location_alt, size: 18),
                        label: const Text('Update'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRemove,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        label: Text(
                          'Remove',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(LocationType type) {
    switch (type) {
      case LocationType.home:
        return Icons.home;
      case LocationType.work:
        return Icons.work;
    }
  }

  Color _getColorForType(LocationType type, ThemeData theme) {
    switch (type) {
      case LocationType.home:
        return Colors.blue;
      case LocationType.work:
        return Colors.orange;
    }
  }
}
