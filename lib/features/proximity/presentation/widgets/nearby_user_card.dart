import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../domain/entities/nearby_user.dart';

/// Card widget displaying a nearby user with optimized image loading.
class NearbyUserCard extends StatelessWidget {
  final NearbyUser user;
  final VoidCallback? onTap;
  final VoidCallback? onConnect;

  const NearbyUserCard({
    super.key,
    required this.user,
    this.onTap,
    this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar with optimized loading
              _UserAvatar(
                photoUrl: user.photoUrl,
                displayName: user.displayName ?? 'U',
                proximity: user.proximity,
              ),
              const SizedBox(width: 12),

              // User info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and proximity indicator
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.displayName ?? 'Unknown User',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _ProximityBadge(proximity: user.proximity),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Bio
                    if (user.bio != null && user.bio!.isNotEmpty)
                      Text(
                        user.bio!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    const SizedBox(height: 8),

                    // Distance and signal info
                    Row(
                      children: [
                        Icon(
                          Icons.straighten,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '~${user.estimatedDistance.toStringAsFixed(1)}m',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _SignalIndicator(rssi: user.rssi),
                      ],
                    ),
                  ],
                ),
              ),

              // Connect button
              if (onConnect != null && !user.isConnected)
                IconButton(
                  onPressed: onConnect,
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'Connect',
                ),

              if (user.isConnected)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_circle,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Optimized user avatar with cached network image.
class _UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String displayName;
  final BleProximity proximity;

  const _UserAvatar({
    this.photoUrl,
    required this.displayName,
    required this.proximity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Proximity ring color
    final ringColor = switch (proximity) {
      BleProximity.immediate => theme.colorScheme.primary,
      BleProximity.near => theme.colorScheme.secondary,
      BleProximity.far => theme.colorScheme.outline,
      BleProximity.veryFar => theme.colorScheme.outlineVariant,
      BleProximity.unknown => theme.colorScheme.outlineVariant,
    };

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: CircleAvatar(
        radius: 26,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: photoUrl != null
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: photoUrl!,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _AvatarPlaceholder(
                    displayName: displayName,
                  ),
                  errorWidget: (_, __, ___) => _AvatarPlaceholder(
                    displayName: displayName,
                  ),
                  // Optimize memory usage
                  memCacheWidth: 104, // 2x for retina
                  memCacheHeight: 104,
                ),
              )
            : _AvatarPlaceholder(displayName: displayName),
      ),
    );
  }
}

/// Placeholder for avatar when no image.
class _AvatarPlaceholder extends StatelessWidget {
  final String displayName;

  const _AvatarPlaceholder({required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Proximity badge widget.
class _ProximityBadge extends StatelessWidget {
  final BleProximity proximity;

  const _ProximityBadge({required this.proximity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (color, label) = switch (proximity) {
      BleProximity.immediate => (theme.colorScheme.primary, 'Very Close'),
      BleProximity.near => (theme.colorScheme.secondary, 'Nearby'),
      BleProximity.far => (theme.colorScheme.outline, 'In Range'),
      BleProximity.veryFar => (theme.colorScheme.outlineVariant, 'Far Away'),
      BleProximity.unknown => (theme.colorScheme.outlineVariant, 'Unknown'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Signal strength indicator.
class _SignalIndicator extends StatelessWidget {
  final int rssi;

  const _SignalIndicator({required this.rssi});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Normalize RSSI to 0-4 bars
    final bars = switch (rssi) {
      >= -50 => 4,
      >= -60 => 3,
      >= -70 => 2,
      >= -80 => 1,
      _ => 0,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final isActive = index < bars;
        return Container(
          width: 3,
          height: 6 + (index * 2).toDouble(),
          margin: const EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
