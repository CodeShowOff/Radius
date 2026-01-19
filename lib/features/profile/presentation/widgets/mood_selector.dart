import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/profile_bloc.dart';

/// Quick mood selector widget for setting current mood.
class MoodSelector extends StatelessWidget {
  final bool showLabel;
  final bool compact;

  const MoodSelector({
    super.key,
    this.showLabel = true,
    this.compact = false,
  });

  static const moods = {
    '😊 Chill': '😊 Chill',
    '🤓 Focused': '🤓 Focused',
    '🧠 Deep talk': '🧠 Deep talk',
    '😂 Fun': '😂 Fun',
  };

  void _updateMood(BuildContext context, String? mood) {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final profileState = context.read<ProfileBloc>().state;
    if (profileState is! ProfileLoaded) return;

    final updatedProfile = profileState.profile.copyWith(
      mood: mood,
      updatedAt: DateTime.now(),
    );

    context.read<ProfileBloc>().add(ProfileUpdateRequested(updatedProfile));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        final currentMood = state is ProfileLoaded ? state.profile.mood : null;

        if (compact) {
          return _buildCompactSelector(context, currentMood);
        }

        return _buildFullSelector(context, currentMood);
      },
    );
  }

  Widget _buildCompactSelector(BuildContext context, String? currentMood) {
    final theme = Theme.of(context);
    
    return PopupMenuButton<String?>(
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: currentMood != null
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sentiment_satisfied_alt,
              size: 18,
              color: currentMood != null
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Text(
              currentMood ?? 'Set Mood',
              style: theme.textTheme.labelMedium?.copyWith(
                color: currentMood != null
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      onSelected: (mood) => _updateMood(context, mood),
      itemBuilder: (context) => [
        PopupMenuItem<String?>(
          value: null,
          child: Row(
            children: [
              Icon(Icons.clear, size: 20, color: theme.colorScheme.outline),
              const SizedBox(width: 12),
              const Text('Clear Mood'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...moods.entries.map((entry) {
          final isSelected = currentMood == entry.value;
          return PopupMenuItem<String?>(
            value: entry.value,
            child: Row(
              children: [
                if (isSelected)
                  Icon(Icons.check, size: 20, color: theme.colorScheme.primary)
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 12),
                Text(entry.key),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFullSelector(BuildContext context, String? currentMood) {
    final theme = Theme.of(context);

    return Card(
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
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.sentiment_satisfied_alt,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Mood',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Let others know how you\'re feeling',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('None'),
                  selected: currentMood == null,
                  onSelected: (selected) {
                    if (selected) _updateMood(context, null);
                  },
                  selectedColor: theme.colorScheme.surfaceContainerHighest,
                ),
                ...moods.entries.map((entry) {
                  return FilterChip(
                    label: Text(entry.key),
                    selected: currentMood == entry.value,
                    onSelected: (selected) {
                      _updateMood(context, selected ? entry.value : null);
                    },
                    selectedColor: theme.colorScheme.secondaryContainer,
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
