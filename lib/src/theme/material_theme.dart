/// Material chrome (dialogs, buttons, menus, switches) derived from the
/// active [ReadmeTheme], so app surfaces follow the document theme instead
/// of Material 3's stock purple seed scheme.
library;

import 'package:flutter/material.dart';

import 'readme_theme.dart';

ThemeData buildMaterialTheme(ReadmeTheme t) {
  final dark = t.background.computeLuminance() < 0.5;
  // Dialog/menu surfaces sit one step off the canvas so they read as
  // panels on both light and dark themes.
  final surface = Color.lerp(
      t.background, dark ? Colors.white : Colors.black, dark ? 0.08 : 0.03)!;
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: t.accent,
    surface: t.background,
    onSurface: t.foreground,
    // The M3 elevation tint is what turns every surface purple-ish.
    surfaceTint: Colors.transparent,
  );
  final family = t.fontFamily.isEmpty ? null : t.fontFamily.first;
  final fallback = t.fontFamily.length > 1 ? t.fontFamily.sublist(1) : null;

  RoundedRectangleBorder rounded(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return ThemeData(
    colorScheme: scheme,
    fontFamily: family,
    fontFamilyFallback: fallback,
    scaffoldBackgroundColor: t.background,
    splashFactory: NoSplash.splashFactory,
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded(10),
      titleTextStyle: TextStyle(
        color: t.foreground,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
      contentTextStyle: TextStyle(
        color: t.foreground,
        fontSize: 13.5,
        height: 1.45,
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(rounded(8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: rounded(8),
      textStyle: TextStyle(
        color: t.foreground,
        fontSize: 13,
        fontFamily: family,
        fontFamilyFallback: fallback,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor:
            t.accent.computeLuminance() < 0.5 ? Colors.white : Colors.black,
        shape: rounded(7),
        visualDensity: VisualDensity.compact,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent,
        shape: rounded(7),
        visualDensity: VisualDensity.compact,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? t.accent
              : t.hintColor.withValues(alpha: 0.4)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
    dividerTheme: DividerThemeData(
        color: t.foreground.withValues(alpha: dark ? 0.15 : 0.1)),
  );
}
