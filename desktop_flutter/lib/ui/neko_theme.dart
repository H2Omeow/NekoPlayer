import 'dart:io';

import 'package:flutter/material.dart';

import 'bundled_fonts.dart';

/// Spacing and radius scale shared by every screen. Keep layouts on these
/// values instead of ad hoc numbers so pages line up with each other.
abstract final class NekoSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class NekoRadius {
  static const cover = 6.0;
  static const control = 8.0;
  static const card = 12.0;
  static const panel = 12.0;
  static const artwork = 16.0;
  static const dialog = 20.0;
}

/// Colours that have no Material role: the window canvas behind the panels
/// and the accent used for "playing" and "liked" states.
@immutable
class NekoPalette extends ThemeExtension<NekoPalette> {
  const NekoPalette({
    required this.canvas,
    required this.panel,
    required this.hover,
    required this.accent,
  });

  final Color canvas;
  final Color panel;
  final Color hover;
  final Color accent;

  /// Falls back to values derived from the colour scheme so widgets also
  /// work under a plain [ThemeData].
  static NekoPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<NekoPalette>() ??
        NekoPalette(
          canvas: theme.colorScheme.surfaceContainerLowest,
          panel: theme.colorScheme.surface,
          hover: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          accent: theme.colorScheme.primary,
        );
  }

  @override
  NekoPalette copyWith({
    Color? canvas,
    Color? panel,
    Color? hover,
    Color? accent,
  }) => NekoPalette(
    canvas: canvas ?? this.canvas,
    panel: panel ?? this.panel,
    hover: hover ?? this.hover,
    accent: accent ?? this.accent,
  );

  @override
  NekoPalette lerp(NekoPalette? other, double t) => other == null
      ? this
      : NekoPalette(
          canvas: Color.lerp(canvas, other.canvas, t)!,
          panel: Color.lerp(panel, other.panel, t)!,
          hover: Color.lerp(hover, other.hover, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
        );
}

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFF0546E),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF4B1A26),
  onPrimaryContainer: Color(0xFFFFD9DF),
  secondary: Color(0xFFC9C3CB),
  onSecondary: Color(0xFF1D1B1E),
  secondaryContainer: Color(0xFF333034),
  onSecondaryContainer: Color(0xFFF2EEF2),
  tertiary: Color(0xFF8FCBC4),
  onTertiary: Color(0xFF00201D),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF141315),
  onSurface: Color(0xFFEEEAEE),
  onSurfaceVariant: Color(0xFFABA6AE),
  surfaceContainerLowest: Color(0xFF0B0A0C),
  surfaceContainerLow: Color(0xFF1B1A1C),
  surfaceContainer: Color(0xFF211F22),
  surfaceContainerHigh: Color(0xFF2A282B),
  surfaceContainerHighest: Color(0xFF353336),
  outline: Color(0xFF7A757D),
  outlineVariant: Color(0xFF302E32),
  inverseSurface: Color(0xFFEEEAEE),
  onInverseSurface: Color(0xFF1D1B1E),
  inversePrimary: Color(0xFFB8304B),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFD03A56),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFDDE2),
  onPrimaryContainer: Color(0xFF3E0011),
  secondary: Color(0xFF5E5961),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE7E2E8),
  onSecondaryContainer: Color(0xFF1D1A1E),
  tertiary: Color(0xFF00696F),
  onTertiary: Color(0xFFFFFFFF),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFFCFAFC),
  onSurface: Color(0xFF1C1A1D),
  onSurfaceVariant: Color(0xFF5E5961),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF5F2F5),
  surfaceContainer: Color(0xFFEFECEF),
  surfaceContainerHigh: Color(0xFFE9E5E9),
  surfaceContainerHighest: Color(0xFFE2DEE2),
  outline: Color(0xFF8A858D),
  outlineVariant: Color(0xFFDDD8DD),
  inverseSurface: Color(0xFF313033),
  onInverseSurface: Color(0xFFF3EFF3),
  inversePrimary: Color(0xFFFFB1BE),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

String? _platformFont() {
  if (Platform.isWindows) return 'Microsoft YaHei UI';
  return null;
}

// The bundled font comes first so Chinese text looks the same on every
// system, including minimal Linux installs without CJK fonts.
const _fontFallback = [bundledCjkFamily, 'Segoe UI', 'sans-serif'];

// Component themes copy these styles directly, so the font family and
// fallbacks must be part of each style rather than only of ThemeData.
TextTheme _textTheme(ColorScheme colors, String? customFont) {
  TextStyle style(double size, FontWeight weight, double height) => TextStyle(
    fontFamily: customFont ?? _platformFont(),
    fontFamilyFallback: _fontFallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: 0,
    color: colors.onSurface,
  );
  return TextTheme(
    displaySmall: style(32, FontWeight.w700, 1.25),
    headlineMedium: style(28, FontWeight.w700, 1.3),
    headlineSmall: style(22, FontWeight.w700, 1.3),
    titleLarge: style(18, FontWeight.w600, 1.35),
    titleMedium: style(15, FontWeight.w600, 1.4),
    titleSmall: style(14, FontWeight.w600, 1.4),
    bodyLarge: style(15, FontWeight.w400, 1.5),
    bodyMedium: style(14, FontWeight.w400, 1.5),
    bodySmall: style(
      12,
      FontWeight.w400,
      1.45,
    ).copyWith(color: colors.onSurfaceVariant),
    labelLarge: style(14, FontWeight.w600, 1.3),
    labelMedium: style(12, FontWeight.w500, 1.3),
    labelSmall: style(
      11,
      FontWeight.w500,
      1.3,
    ).copyWith(color: colors.onSurfaceVariant),
  );
}

ThemeData nekoTheme({
  Brightness brightness = Brightness.dark,
  double controlAlpha = 1,
  bool wallpaper = false,
  String? customFont,
  bool reduceMotion = false,
}) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? _darkScheme : _lightScheme;
  final alpha = wallpaper ? controlAlpha.clamp(0.2, 1.0) : 1.0;
  final palette = NekoPalette(
    canvas: wallpaper
        ? Colors.transparent
        : dark
        ? const Color(0xFF0B0A0C)
        : const Color(0xFFEAE6EA),
    panel: colors.surface.withValues(alpha: alpha),
    hover: colors.onSurface.withValues(alpha: dark ? 0.06 : 0.05),
    accent: colors.primary,
  );
  final text = _textTheme(colors, customFont);
  final control = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(NekoRadius.control),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    extensions: [palette],
    fontFamily: customFont ?? _platformFont(),
    fontFamilyFallback: _fontFallback,
    textTheme: text,
    scaffoldBackgroundColor: wallpaper ? Colors.transparent : colors.surface,
    canvasColor: wallpaper ? Colors.transparent : colors.surface,
    splashFactory: InkSparkle.splashFactory,
    hoverColor: palette.hover,
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleSpacing: NekoSpace.sm,
      toolbarHeight: 60,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: colors.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow.withValues(alpha: alpha),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NekoRadius.card),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: control,
      contentPadding: const EdgeInsets.symmetric(horizontal: NekoSpace.lg),
      iconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
      selectedColor: colors.onSurface,
      selectedTileColor: colors.onSurface.withValues(alpha: 0.08),
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall,
      minVerticalPadding: 10,
      horizontalTitleGap: NekoSpace.lg,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHigh.withValues(alpha: alpha),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NekoSpace.lg,
        vertical: 14,
      ),
      hintStyle: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      prefixIconColor: colors.onSurfaceVariant,
      suffixIconColor: colors.onSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NekoRadius.control),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NekoRadius.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NekoRadius.control),
        borderSide: BorderSide(color: colors.outline, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const StadiumBorder(),
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outlineVariant),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const StadiumBorder(),
        foregroundColor: colors.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: colors.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      showCheckmark: false,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      color: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onSurface
            : colors.surfaceContainerHigh.withValues(alpha: alpha),
      ),
      labelStyle: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.surface
              : colors.onSurface,
        ),
      ),
      iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 18),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: colors.onSurfaceVariant,
        selectedBackgroundColor: colors.onSurface,
        selectedForegroundColor: colors.surface,
        side: BorderSide(color: colors.outlineVariant),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: colors.onSurface,
      inactiveTrackColor: colors.onSurface.withValues(alpha: 0.18),
      thumbColor: colors.onSurface,
      overlayColor: colors.onSurface.withValues(alpha: 0.08),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      trackShape: const RoundedRectSliderTrackShape(),
      tickMarkShape: SliderTickMarkShape.noTickMark,
      showValueIndicator: ShowValueIndicator.never,
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : colors.outline,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      linearMinHeight: 3,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NekoRadius.dialog),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(NekoRadius.dialog),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: text.bodyMedium,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: text.bodySmall?.copyWith(color: colors.onInverseSurface),
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
      ),
      actionTextColor: colors.inversePrimary,
      width: 420,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: palette.canvas == Colors.transparent
          ? colors.surfaceContainerLowest.withValues(alpha: alpha)
          : palette.canvas,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: colors.secondaryContainer,
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorColor: colors.onSurface,
      labelColor: colors.onSurface,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: text.titleSmall,
      unselectedLabelStyle: text.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      tabAlignment: TabAlignment.start,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(
        colors.onSurface.withValues(alpha: 0.22),
      ),
    ),
    // FadeForwards paints colorScheme.surface between the two routes by
    // default, which covers the window wallpaper during page changes.
    // Performance mode skips route animations entirely: on a 4K screen each
    // transition composites two full-resolution scenes and can cause drops.
    pageTransitionsTheme: reduceMotion
        ? const PageTransitionsTheme(
            builders: {
              TargetPlatform.linux: _NoTransitionsBuilder(),
              TargetPlatform.windows: _NoTransitionsBuilder(),
              TargetPlatform.macOS: _NoTransitionsBuilder(),
              TargetPlatform.android: _NoTransitionsBuilder(),
              TargetPlatform.iOS: _NoTransitionsBuilder(),
              TargetPlatform.fuchsia: _NoTransitionsBuilder(),
            },
          )
        : const PageTransitionsTheme(
            builders: {
              TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(
                backgroundColor: Colors.transparent,
              ),
              TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(
                backgroundColor: Colors.transparent,
              ),
              TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(
                backgroundColor: Colors.transparent,
              ),
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
                backgroundColor: Colors.transparent,
              ),
            },
          ),
  );
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
