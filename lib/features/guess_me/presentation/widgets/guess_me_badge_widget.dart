import 'package:flutter/material.dart';

import '../../domain/entities/guess_me_stats.dart';

/// Extension to get Flutter Color and IconData from badge tier.
extension GuessmeBadgeTierUI on GuessmeBadgeTier {
  Color get color => Color(colorValue);

  IconData get icon {
    switch (this) {
      case GuessmeBadgeTier.none:
        return Icons.help_outline;
      case GuessmeBadgeTier.beginner:
        return Icons.psychology;
      case GuessmeBadgeTier.intermediate:
        return Icons.trending_up;
      case GuessmeBadgeTier.skilled:
        return Icons.star;
      case GuessmeBadgeTier.expert:
        return Icons.emoji_events;
      case GuessmeBadgeTier.master:
        return Icons.military_tech;
    }
  }
}

/// Widget to display a GuessMe badge.
/// Can be displayed on profiles and nearby user cards.
class GuessmeBadgeWidget extends StatelessWidget {
  final GuessmeBadgeTier badge;
  final bool showLabel;
  final double size;

  const GuessmeBadgeWidget({
    super.key,
    required this.badge,
    this.showLabel = true,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    if (badge == GuessmeBadgeTier.none) {
      return const SizedBox.shrink();
    }

    if (showLabel) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badge.color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: badge.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              badge.icon,
              size: size * 0.7,
              color: badge.color,
            ),
            const SizedBox(width: 4),
            Text(
              badge.displayName,
              style: TextStyle(
                color: badge.color,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.5,
              ),
            ),
          ],
        ),
      );
    }

    // Icon-only version
    return Tooltip(
      message: 'GuessMe ${badge.displayName}',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: badge.color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: badge.color.withValues(alpha: 0.5)),
        ),
        child: Icon(
          badge.icon,
          size: size,
          color: badge.color,
        ),
      ),
    );
  }
}

/// A small badge indicator that shows on profile cards.
class GuessmeBadgeIndicator extends StatelessWidget {
  final GuessmeBadgeTier badge;

  const GuessmeBadgeIndicator({
    super.key,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    if (badge == GuessmeBadgeTier.none) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: badge.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: badge.color.withValues(alpha: 0.3),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        badge.icon,
        size: 12,
        color: Colors.white,
      ),
    );
  }
}

/// Extension to get badge tier from Firestore data.
extension GuessmeBadgeTierFromInt on int {
  GuessmeBadgeTier toGuessmeBadgeTier() {
    if (this >= 100) return GuessmeBadgeTier.master;
    if (this >= 50) return GuessmeBadgeTier.expert;
    if (this >= 25) return GuessmeBadgeTier.skilled;
    if (this >= 10) return GuessmeBadgeTier.intermediate;
    if (this >= 5) return GuessmeBadgeTier.beginner;
    return GuessmeBadgeTier.none;
  }
}
