import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A themed card widget inspired by modern smart-home UIs.
///
/// Uses colors exclusively from [ThemeData] — no inline color values.
/// Pass [gradient] = true for a premium purple-gradient header effect.
class SmartHomeCard extends StatelessWidget {
  const SmartHomeCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.gradient = false,
    this.child,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// When `true`, the card header area renders with a vibrant purple gradient.
  final bool gradient;

  /// Optional body widget below the title row.
  final Widget? child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      // Card styling comes from ThemeData.cardTheme
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: gradient
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      cs.primary.withValues(alpha: isDark ? 0.25 : 0.10),
                      cs.secondary.withValues(alpha: isDark ? 0.10 : 0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header row ──────────────────────────────────────────
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: cs.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),

              // ── Body ────────────────────────────────────────────────
              if (child != null) ...[
                const SizedBox(height: 14),
                child!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A modern purple filled button matching the smart-home aesthetic.
///
/// All styling comes from [ThemeData.elevatedButtonTheme].
/// For a gradient look, pass [gradient] = true.
class PurpleButton extends StatelessWidget {
  const PurpleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool gradient;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget button;

    if (icon != null) {
      button = ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      );
    } else {
      button = ElevatedButton(
        onPressed: onPressed,
        child: Text(label),
      );
    }

    // Wrap for full-width if requested
    if (expand) {
      button = SizedBox(
        width: double.infinity,
        height: 52,
        child: button,
      );
    }

    // Gradient wrapper
    if (gradient && onPressed != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Theme(
          data: theme.copyWith(
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: theme.elevatedButtonTheme.style?.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                shadowColor: WidgetStateProperty.all(Colors.transparent),
                surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
              ),
            ),
          ),
          child: button,
        ),
      );
    }

    return button;
  }
}

/// A pill-shaped filter chip row (like "Outside", "Living room", "Bedroom").
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == selectedIndex;
          return Padding(
            padding: EdgeInsets.only(right: i < labels.length - 1 ? 10 : 0),
            child: ChoiceChip(
              label: Text(labels[i]),
              selected: selected,
              onSelected: (_) => onSelected(i),
              selectedColor: cs.primary,
              backgroundColor:
                  isDark ? const Color(0xFF1E1E28) : const Color(0xFFF0F0F6),
              labelStyle: TextStyle(
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 13,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide(
                color: selected
                    ? cs.primary
                    : (isDark
                        ? const Color(0xFF2A2A36)
                        : const Color(0xFFE2E2EC)),
              ),
              showCheckmark: false,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          );
        }),
      ),
    );
  }
}
