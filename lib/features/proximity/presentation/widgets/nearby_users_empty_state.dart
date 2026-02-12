import 'package:flutter/material.dart';

/// Empty state widget for nearby users screen.
class NearbyUsersEmptyState extends StatelessWidget {
  final bool isScanning;
  final bool hasSearchedAwhile;
  final VoidCallback? onRetry;

  const NearbyUsersEmptyState({
    super.key,
    this.isScanning = false,
    this.hasSearchedAwhile = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated radar icon
                _RadarAnimation(isAnimating: isScanning),
                const SizedBox(height: 24),

                // Title
                Text(
                  isScanning
                      ? (hasSearchedAwhile
                          ? 'No one nearby yet'
                          : 'Searching for people...')
                      : 'No one nearby',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  isScanning
                      ? (hasSearchedAwhile
                          ? 'Still scanning in the foreground.\nTry restarting the scan or ask the other phone to open Nearby too.'
                          : 'Looking for other Radius users within range.\nThis may take a moment.')
                      : 'There are no Radius users nearby right now.\nTry again later or move to a different location.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Retry/restart scan button.
                if (onRetry != null && (!isScanning || hasSearchedAwhile))
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(isScanning ? 'Restart Scan' : 'Scan Again'),
                  ),

                // Tips
                if (!isScanning) ...[
                  const SizedBox(height: 48),
                  _Tips(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Animated radar visualization.
class _RadarAnimation extends StatefulWidget {
  final bool isAnimating;

  const _RadarAnimation({required this.isAnimating});

  @override
  State<_RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<_RadarAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.8, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_RadarAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnimating && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isAnimating && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated ripple rings
          if (widget.isAnimating)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  width: 120 * _scaleAnimation.value,
                  height: 120 * _scaleAnimation.value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.primary
                          .withValues(alpha: _opacityAnimation.value),
                      width: 2,
                    ),
                  ),
                );
              },
            ),

          // Second ripple (offset)
          if (widget.isAnimating)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = (_controller.value + 0.5) % 1.0;
                final scale = 0.5 + offset;
                final opacity = 0.8 * (1 - offset);

                return Container(
                  width: 120 * scale,
                  height: 120 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          theme.colorScheme.primary.withValues(alpha: opacity),
                      width: 2,
                    ),
                  ),
                );
              },
            ),

          // Center icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isAnimating
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(
              widget.isAnimating ? Icons.radar : Icons.person_search,
              size: 32,
              color: widget.isAnimating
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tips section for empty state.
class _Tips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Tips',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _TipItem(
            icon: Icons.bluetooth,
            text: 'Make sure Bluetooth is enabled',
          ),
          const _TipItem(
            icon: Icons.phone_iphone,
            text: 'Keep the app open for scanning',
          ),
          const _TipItem(
            icon: Icons.visibility,
            text: 'Others need to have visibility enabled',
          ),
        ],
      ),
    );
  }
}

/// Single tip item.
class _TipItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TipItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
