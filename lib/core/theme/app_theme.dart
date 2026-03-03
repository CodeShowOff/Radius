import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern smart-home style theme configuration.
///
/// Provides premium dark & light themes with vibrant purple accents,
/// strong contrast, and a cohesive Material 3 design language.
abstract class AppTheme {
  // ──────────────────────────── Brand Colors ────────────────────────────

  /// Primary purple accent.
  static const Color primaryColor = Color(0xFF8B2FC9);

  /// Secondary purple (lighter for gradients).
  static const Color secondaryColor = Color(0xFFA040D8);

  /// Tertiary accent – electric cyan for highlights.
  static const Color accentColor = Color(0xFF00D9FF);

  // ──────────────────────────── Semantic Colors ─────────────────────────

  static const Color successColor = Color(0xFF22C55E);
  static const Color warningColor = Color(0xFFFBBF24);
  static const Color errorColor = Color(0xFFEF4444);

  // ──────────────────────────── Proximity Colors ────────────────────────

  static const Color nearbyCloseColor = Color(0xFF22C55E); // < 3 m
  static const Color nearbyMediumColor = Color(0xFFFBBF24); // 3–7 m
  static const Color nearbyFarColor = Color(0xFF8B2FC9); // 7–10 m

  // ──────────────────────────── Surface palette ─────────────────────────

  // Dark mode surfaces
  static const Color _darkBg = Color(0xFF0B0B0F);
  static const Color _darkSurface = Color(0xFF16161D);
  static const Color _darkCard = Color(0xFF1E1E28);
  static const Color _darkCardBorder = Color(0xFF2A2A36);

  // Light mode surfaces
  static const Color _lightBg = Color(0xFFF8F8FC);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightCard = Color(0xFFF0F0F6);
  static const Color _lightCardBorder = Color(0xFFE2E2EC);

  // ──────────────────────────── Gradient helpers ────────────────────────

  /// Vibrant purple gradient used for hero elements & CTA buttons.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF8B2FC9), Color(0xFFA040D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Subtle surface gradient for cards / sections with a premium feel.
  static const LinearGradient darkSurfaceGradient = LinearGradient(
    colors: [Color(0xFF16161D), Color(0xFF1A1A24)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ══════════════════════════════════════════════════════════════════════
  //  DARK THEME
  // ══════════════════════════════════════════════════════════════════════

  static ThemeData get darkTheme {
    const brightness = Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF5C1A96),
      onPrimaryContainer: const Color(0xFFE8DEFF),
      secondary: secondaryColor,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFF6B1FAA),
      onSecondaryContainer: const Color(0xFFF3E8FF),
      tertiary: accentColor,
      onTertiary: Colors.black,
      tertiaryContainer: const Color(0xFF005F6B),
      onTertiaryContainer: const Color(0xFFCCF8FF),
      error: errorColor,
      onError: Colors.white,
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: _darkSurface,
      onSurface: Colors.white,
      surfaceContainerHighest: _darkCard,
      onSurfaceVariant: const Color(0xFFCAC4D0),
      outline: const Color(0xFF938F99),
      outlineVariant: const Color(0xFF49454F),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFFE6E1E5),
      onInverseSurface: const Color(0xFF1C1B1F),
      inversePrimary: const Color(0xFF6200EE),
      surfaceTint: primaryColor,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: _darkBg,
      cardColor: _darkCard,
      cardBorder: _darkCardBorder,
      dividerColor: const Color(0xFF2A2A36),
      brightness: brightness,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  LIGHT THEME
  // ══════════════════════════════════════════════════════════════════════

  static ThemeData get lightTheme {
    const brightness = Brightness.light;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFEADDFF),
      onPrimaryContainer: const Color(0xFF21005E),
      secondary: secondaryColor,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFF3E8FF),
      onSecondaryContainer: const Color(0xFF2D004F),
      tertiary: const Color(0xFF0097A7),
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFCCF8FF),
      onTertiaryContainer: const Color(0xFF001F24),
      error: errorColor,
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
      surface: _lightSurface,
      onSurface: const Color(0xFF1C1B1F),
      surfaceContainerHighest: _lightCard,
      onSurfaceVariant: const Color(0xFF49454F),
      outline: const Color(0xFF79747E),
      outlineVariant: const Color(0xFFCAC4D0),
      shadow: const Color(0x40000000),
      scrim: const Color(0x40000000),
      inverseSurface: const Color(0xFF313033),
      onInverseSurface: const Color(0xFFF4EFF4),
      inversePrimary: const Color(0xFFD0BCFF),
      surfaceTint: primaryColor,
    );

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: _lightBg,
      cardColor: _lightCard,
      cardBorder: _lightCardBorder,
      dividerColor: const Color(0xFFE2E2EC),
      brightness: brightness,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  //  SHARED BUILDER
  // ══════════════════════════════════════════════════════════════════════

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color cardColor,
    required Color cardBorder,
    required Color dividerColor,
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1B1F);
    final subtitleColor =
        isDark ? const Color(0xFFB0B0BE) : const Color(0xFF5E5E6E);

    // Typography scale
    final textTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: textColor,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: textColor,
        letterSpacing: -0.25,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      titleSmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: subtitleColor,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: subtitleColor,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textColor,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: subtitleColor,
        letterSpacing: 0.5,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,

      // ── AppBar ───────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBg,
        foregroundColor: textColor,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        iconTheme: IconThemeData(color: textColor, size: 22),
      ),

      // ── Card ─────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          side: BorderSide(color: cardBorder, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      ),

      // ── Elevated Button ──────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      // ── Filled Button ────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      // ── Outlined Button ──────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      // ── Text Button ──────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),

      // ── Icon Button ──────────────────────────────────────────────────
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textColor,
        ),
      ),

      // ── Floating Action Button ───────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // ── Icon theme ───────────────────────────────────────────────────
      iconTheme: IconThemeData(color: textColor, size: 22),

      // ── Input decoration ─────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? _darkCard : _lightCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        hintStyle: TextStyle(color: subtitleColor, fontSize: 14),
        labelStyle: TextStyle(color: subtitleColor, fontSize: 14),
      ),

      // ── Chip theme ───────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? _darkCard : _lightCard,
        selectedColor: colorScheme.primary,
        labelStyle: TextStyle(color: textColor, fontSize: 13),
        secondaryLabelStyle:
            const TextStyle(color: Colors.white, fontSize: 13),
        side: BorderSide(color: cardBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),

      // ── Bottom Navigation Bar ────────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? _darkSurface : _lightSurface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: subtitleColor,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
      ),

      // ── Navigation Bar (M3) ──────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? _darkSurface : _lightSurface,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.15),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: subtitleColor,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary, size: 24);
          }
          return IconThemeData(color: subtitleColor, size: 24);
        }),
      ),

      // ── Divider ──────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),

      // ── Dialog ───────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? _darkCard : _lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: subtitleColor,
        ),
      ),

      // ── Bottom Sheet ─────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? _darkSurface : _lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: subtitleColor.withValues(alpha: 0.4),
        dragHandleSize: const Size(40, 4),
      ),

      // ── Snackbar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2A2A36) : const Color(0xFF313033),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
      ),

      // ── List Tile ────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: textColor,
        iconColor: textColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ── Switch ───────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return subtitleColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return isDark ? const Color(0xFF2A2A36) : const Color(0xFFD6D6E0);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── Slider ───────────────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor:
            isDark ? const Color(0xFF2A2A36) : const Color(0xFFD6D6E0),
        thumbColor: Colors.white,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),

      // ── Progress Indicator ───────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor:
            isDark ? const Color(0xFF2A2A36) : const Color(0xFFD6D6E0),
        circularTrackColor:
            isDark ? const Color(0xFF2A2A36) : const Color(0xFFD6D6E0),
      ),

      // ── Tab Bar ──────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: subtitleColor,
        indicatorColor: colorScheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
        dividerColor: Colors.transparent,
      ),

      // ── Tooltip ──────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A36) : const Color(0xFF313033),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),

      // ── Page Transitions ─────────────────────────────────────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // ── Splash / Highlight ───────────────────────────────────────────
      splashColor: colorScheme.primary.withValues(alpha: 0.08),
      highlightColor: colorScheme.primary.withValues(alpha: 0.06),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
