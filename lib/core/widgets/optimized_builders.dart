import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Mixin for optimized BlocBuilder usage.
/// 
/// Provides helper methods for selective rebuilds and performance monitoring.
mixin OptimizedBlocMixin<T extends StatefulWidget> on State<T> {
  /// Build a widget that only rebuilds when specific state changes.
  Widget selectiveBuilder<B extends BlocBase<S>, S>({
    required BlocWidgetSelector<S, S> selector,
    required BlocWidgetBuilder<S> builder,
    BlocBuilderCondition<S>? buildWhen,
  }) {
    return BlocSelector<B, S, S>(
      selector: selector,
      builder: builder,
    );
  }
}

/// Extension on BlocBuilder for common optimization patterns.
extension OptimizedBlocBuilderX<B extends BlocBase<S>, S> on BlocBuilder<B, S> {
  /// Create a builder that only rebuilds when the selected value changes.
  static BlocSelector<B, S, T> select<B extends BlocBase<S>, S, T>({
    Key? key,
    required T Function(S state) selector,
    required Widget Function(BuildContext context, T value) builder,
    B? bloc,
  }) {
    return BlocSelector<B, S, T>(
      key: key,
      bloc: bloc,
      selector: selector,
      builder: builder,
    );
  }
}

/// Widget that prevents rebuilds of expensive children.
/// 
/// Use this to wrap widgets that don't need to rebuild
/// when parent state changes.
class RebuildBarrier extends StatefulWidget {
  final Widget child;
  final bool shouldRebuild;

  const RebuildBarrier({
    super.key,
    required this.child,
    this.shouldRebuild = false,
  });

  @override
  State<RebuildBarrier> createState() => _RebuildBarrierState();
}

class _RebuildBarrierState extends State<RebuildBarrier> {
  late Widget _cachedChild;

  @override
  void initState() {
    super.initState();
    _cachedChild = widget.child;
  }

  @override
  void didUpdateWidget(RebuildBarrier oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldRebuild) {
      _cachedChild = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) => _cachedChild;
}

/// Widget that defers building until after the frame.
/// 
/// Useful for expensive widgets that can be built after
/// the initial frame to improve perceived performance.
class DeferredBuilder extends StatefulWidget {
  final WidgetBuilder builder;
  final Widget placeholder;
  final Duration delay;

  const DeferredBuilder({
    super.key,
    required this.builder,
    this.placeholder = const SizedBox.shrink(),
    this.delay = Duration.zero,
  });

  @override
  State<DeferredBuilder> createState() => _DeferredBuilderState();
}

class _DeferredBuilderState extends State<DeferredBuilder> {
  bool _isBuilt = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isBuilt = true);
      });
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) setState(() => _isBuilt = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isBuilt ? widget.builder(context) : widget.placeholder;
  }
}

/// Optimized ListView builder with automatic item caching.
/// 
/// Wraps items in AutomaticKeepAliveClientMixin to prevent
/// rebuilds when scrolling.
class OptimizedListView<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final bool reverse;
  final ScrollPhysics? physics;
  final bool keepAlive;
  final Widget? separatorBuilder;

  const OptimizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.reverse = false,
    this.physics,
    this.keepAlive = true,
    this.separatorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (separatorBuilder != null) {
      return ListView.separated(
        controller: controller,
        padding: padding,
        reverse: reverse,
        physics: physics,
        itemCount: items.length,
        separatorBuilder: (_, __) => separatorBuilder!,
        itemBuilder: (context, index) {
          final item = items[index];
          if (keepAlive) {
            return _KeepAliveWrapper(
              child: itemBuilder(context, item, index),
            );
          }
          return itemBuilder(context, item, index);
        },
      );
    }

    return ListView.builder(
      controller: controller,
      padding: padding,
      reverse: reverse,
      physics: physics,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (keepAlive) {
          return _KeepAliveWrapper(
            child: itemBuilder(context, item, index),
          );
        }
        return itemBuilder(context, item, index);
      },
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
