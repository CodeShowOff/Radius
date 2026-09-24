import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Optimized avatar widget with caching and placeholder.
/// 
/// Uses cached_network_image for efficient image loading and caching.
/// Falls back to initials when no image URL provided.
class CachedAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const CachedAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 24,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fgColor = foregroundColor ?? theme.colorScheme.onPrimaryContainer;

    if (imageUrl == null || imageUrl!.isEmpty) {
      return _InitialsAvatar(
        name: name,
        radius: radius,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
        backgroundColor: bgColor,
      ),
      placeholder: (context, url) => _InitialsAvatar(
        name: name,
        radius: radius,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
      ),
      errorWidget: (context, url, error) => _InitialsAvatar(
        name: name,
        radius: radius,
        backgroundColor: bgColor,
        foregroundColor: fgColor,
      ),
      // Cache configuration
      memCacheWidth: (radius * 4).toInt(),
      memCacheHeight: (radius * 4).toInt(),
      maxWidthDiskCache: 200,
      maxHeightDiskCache: 200,
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  const _InitialsAvatar({
    required this.name,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(name);
    
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Text(
        initials,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
