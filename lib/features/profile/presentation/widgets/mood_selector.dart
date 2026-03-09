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
    '😊 Chill': 'Chill',
    '🤓 Focused': 'Focused',
    '🧠 Deep talk': 'Deep talk',
    '😂 Fun': 'Fun',
  };

  static const _moodIcons = {
    '😊 Chill': Icons.sentiment_satisfied_alt,
    '🤓 Focused': Icons.psychology,
    '🧠 Deep talk': Icons.forum,
    '😂 Fun': Icons.celebration,
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
    final displayLabel = currentMood != null
        ? (moods[currentMood] ?? currentMood)
        : 'Set Mood';
    final icon = currentMood != null
        ? (_moodIcons[currentMood] ?? Icons.mood)
        : Icons.mood_outlined;
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
              icon,
              size: 18,
              color: currentMood != null
                  ? theme.colorScheme.secondary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              displayLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: currentMood != null
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      onSelected: (mood) => _updateMood(context, mood),
      itemBuilder: (context) => [
        ...moods.entries.map((entry) {
          final isSelected = currentMood == entry.key;
          return PopupMenuItem<String?>(
            value: entry.key,
            child: Row(
              children: [
                Icon(
                  _moodIcons[entry.key] ?? Icons.mood,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(entry.value),
                if (isSelected) ...[  
                  const Spacer(),
                  Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFullSelector(BuildContext context, String? currentMood) {
    final theme = Theme.of(context);
    final displayLabel = currentMood != null
        ? (moods[currentMood] ?? currentMood)
        : 'Not set';
    final moodIcon = currentMood != null
        ? (_moodIcons[currentMood] ?? Icons.mood)
        : Icons.mood_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              moodIcon,
              size: 22,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mood',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  displayLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Change mood',
            icon: Icon(
              Icons.arrow_drop_down_circle_outlined,
              color: theme.colorScheme.secondary,
              size: 22,
            ),
            onSelected: (mood) => _updateMood(context, mood),
            itemBuilder: (context) => moods.entries.map((entry) {
              final isSelected = currentMood == entry.key;
              return PopupMenuItem<String>(
                value: entry.key,
                child: Row(
                  children: [
                    Icon(
                      _moodIcons[entry.key] ?? Icons.mood,
                      size: 20,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(entry.value),
                    if (isSelected) ...[  
                      const Spacer(),
                      Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
