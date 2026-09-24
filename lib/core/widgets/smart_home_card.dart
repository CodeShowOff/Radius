import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A themed card widget inspired by modern smart-home UIs.
///
/// Uses colors exclusively from [ThemeData] â€” no inline color values.
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
    
    // Pre-compute decoration to avoid rebuilding
    final containerDecoration = gradient
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
        : null;

    // Pre-compute icon background color
    final iconBgColor = icon != null 
        ? cs.primary.withValues(alpha: isDark ? 0.18 : 0.10)
        : null;

    return Card(
      // Card styling comes from ThemeData.cardTheme
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: containerDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // â”€â”€ Header row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconBgColor,
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

              // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

    // Gradient wrapper - optimized to avoid expensive Theme.copyWith
    if (gradient && onPressed != null) {
      // Pre-compute shadow color once
      final shadowColor = theme.colorScheme.primary.withValues(alpha: 0.35);
      
      return Container(
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            minimumSize: expand ? const Size(double.infinity, 52) : null,
          ),
          child: icon != null 
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                    Text(label),
                  ],
                )
              : Text(label),
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
    
    // Pre-compute colors once
    final unselectedBgColor = isDark ? const Color(0xFF1E1E28) : const Color(0xFFF0F0F6);
    final unselectedLabelColor = isDark ? Colors.white70 : Colors.black87;
    final unselectedBorderColor = isDark ? const Color(0xFF2A2A36) : const Color(0xFFE2E2EC);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i < labels.length - 1 ? 10 : 0),
              child: _FilterChip(
                label: labels[i],
                selected: i == selectedIndex,
                onSelected: () => onSelected(i),
                primaryColor: cs.primary,
                unselectedBgColor: unselectedBgColor,
                unselectedLabelColor: unselectedLabelColor,
                unselectedBorderColor: unselectedBorderColor,
              ),
            ),
        ],
      ),
    );
  }
}

/// Optimized individual filter chip to reduce rebuilds.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.primaryColor,
    required this.unselectedBgColor,
    required this.unselectedLabelColor,
    required this.unselectedBorderColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color primaryColor;
  final Color unselectedBgColor;
  final Color unselectedLabelColor;
  final Color unselectedBorderColor;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: primaryColor,
      backgroundColor: unselectedBgColor,
      labelStyle: TextStyle(
        color: selected ? Colors.white : unselectedLabelColor,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      side: BorderSide(
        color: selected ? primaryColor : unselectedBorderColor,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}
