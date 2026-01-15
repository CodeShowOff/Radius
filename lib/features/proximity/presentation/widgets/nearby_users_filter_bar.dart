import 'package:flutter/material.dart';

import '../bloc/nearby_users_bloc.dart';

/// Filter chip bar for nearby users.
class NearbyUsersFilterBar extends StatelessWidget {
  final NearbyUsersFilter selectedFilter;
  final int allCount;
  final int closeCount;
  final int nearbyCount;
  final ValueChanged<NearbyUsersFilter> onFilterChanged;

  const NearbyUsersFilterBar({
    super.key,
    required this.selectedFilter,
    required this.allCount,
    required this.closeCount,
    required this.nearbyCount,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            count: allCount,
            isSelected: selectedFilter == NearbyUsersFilter.all,
            onTap: () => onFilterChanged(NearbyUsersFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Very Close',
            count: closeCount,
            isSelected: selectedFilter == NearbyUsersFilter.close,
            onTap: () => onFilterChanged(NearbyUsersFilter.close),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Nearby',
            count: nearbyCount,
            isSelected: selectedFilter == NearbyUsersFilter.nearby,
            onTap: () => onFilterChanged(NearbyUsersFilter.nearby),
          ),
        ],
      ),
    );
  }
}

/// Single filter chip.
class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.2)
                    : theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}
