import 'package:flutter/material.dart';

/// Shimmer loading skeleton for a post card in the feed.
class PostCardSkeleton extends StatefulWidget {
  const PostCardSkeleton({super.key});

  @override
  State<PostCardSkeleton> createState() => _PostCardSkeletonState();
}

class _PostCardSkeletonState extends State<PostCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          elevation: 0,
          shape: const RoundedRectangleBorder(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header skeleton
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    _ShimmerBox(
                      width: 40,
                      height: 40,
                      borderRadius: 20,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                      animValue: _animation.value,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ShimmerBox(
                          width: 120,
                          height: 14,
                          borderRadius: 4,
                          baseColor: baseColor,
                          highlightColor: highlightColor,
                          animValue: _animation.value,
                        ),
                        const SizedBox(height: 6),
                        _ShimmerBox(
                          width: 80,
                          height: 10,
                          borderRadius: 4,
                          baseColor: baseColor,
                          highlightColor: highlightColor,
                          animValue: _animation.value,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Media skeleton
              _ShimmerBox(
                width: double.infinity,
                height: 300,
                borderRadius: 0,
                baseColor: baseColor,
                highlightColor: highlightColor,
                animValue: _animation.value,
              ),
              // Text skeleton
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(
                      width: double.infinity,
                      height: 12,
                      borderRadius: 4,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                      animValue: _animation.value,
                    ),
                    const SizedBox(height: 8),
                    _ShimmerBox(
                      width: 200,
                      height: 12,
                      borderRadius: 4,
                      baseColor: baseColor,
                      highlightColor: highlightColor,
                      animValue: _animation.value,
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.3),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A single shimmer box with gradient animation.
class _ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color baseColor;
  final Color highlightColor;
  final double animValue;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.baseColor,
    required this.highlightColor,
    required this.animValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(animValue - 1, 0),
          end: Alignment(animValue + 1, 0),
          colors: [
            baseColor,
            highlightColor,
            baseColor,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

/// Shimmer skeleton for the posts grid (profile page).
class PostsGridSkeleton extends StatefulWidget {
  const PostsGridSkeleton({super.key});

  @override
  State<PostsGridSkeleton> createState() => _PostsGridSkeletonState();
}

class _PostsGridSkeletonState extends State<PostsGridSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;
    final highlightColor = theme.colorScheme.surface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: 9,
          itemBuilder: (context, index) {
            return _ShimmerBox(
              width: double.infinity,
              height: double.infinity,
              borderRadius: 0,
              baseColor: baseColor,
              highlightColor: highlightColor,
              animValue: _animation.value,
            );
          },
        );
      },
    );
  }
}
