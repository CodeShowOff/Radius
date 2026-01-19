import 'package:flutter/material.dart';

/// A Scaffold wrapper that properly handles safe areas and gesture navigation.
/// 
/// This widget ensures content doesn't overlap with:
/// - System status bar
/// - System navigation bar
/// - Gesture navigation areas (swipe from edges)
/// - Bottom notches and home indicators
/// 
/// Works correctly in both full screen and regular display modes.
class SafeScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool resizeToAvoidBottomInset;
  
  /// Whether to apply SafeArea to the body.
  /// Default is true for proper gesture navigation handling.
  final bool useSafeArea;
  
  /// Whether to maintain the bottom safe area (for home indicator).
  /// Default is true to prevent content from being hidden.
  final bool maintainBottomViewPadding;
  
  /// Minimum bottom padding to add (useful for scrollable content).
  /// Default is 16.0 for comfortable spacing.
  final double minimumBottomPadding;

  const SafeScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.drawer,
    this.endDrawer,
    this.backgroundColor,
    this.floatingActionButtonLocation,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.resizeToAvoidBottomInset = true,
    this.useSafeArea = true,
    this.maintainBottomViewPadding = true,
    this.minimumBottomPadding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    Widget? bodyWidget = body;

    if (bodyWidget != null && useSafeArea) {
      // Wrap body in SafeArea to handle system UI overlaps and gesture areas
      bodyWidget = SafeArea(
        // Don't apply top safe area if we have an AppBar (it handles it)
        top: appBar == null,
        bottom: true,
        left: true,
        right: true,
        maintainBottomViewPadding: maintainBottomViewPadding,
        child: bodyWidget,
      );
    }

    return Scaffold(
      appBar: appBar,
      body: bodyWidget,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      drawer: drawer,
      endDrawer: endDrawer,
      backgroundColor: backgroundColor,
      floatingActionButtonLocation: floatingActionButtonLocation,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

/// Extension to get safe padding values for manual padding calculations.
extension SafePaddingExtension on BuildContext {
  /// Get the safe bottom padding including gesture navigation area.
  /// Adds a minimum padding for comfortable spacing.
  double get safeBottomPadding {
    final mediaPadding = MediaQuery.of(this).padding.bottom;
    const minPadding = 16.0;
    return mediaPadding + minPadding;
  }

  /// Get total vertical safe padding (top + bottom).
  double get safeVerticalPadding {
    final padding = MediaQuery.of(this).padding;
    return padding.top + padding.bottom;
  }

  /// Get total horizontal safe padding (left + right).
  double get safeHorizontalPadding {
    final padding = MediaQuery.of(this).padding;
    return padding.left + padding.right;
  }
}
