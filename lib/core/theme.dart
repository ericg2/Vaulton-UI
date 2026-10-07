import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const seedColor = Color(0xFF2F6FED);

/// Builds a Material 3 theme tuned to feel at home on each OS:
///  * Android / Web: stock Material 3 (+ Material You dynamic colour on Android).
///  * Windows: Segoe UI, tighter corners, compact density (Fluent-like).
///  * Linux: Cantarell/Ubuntu, GNOME-style generous rounding.
ThemeData buildTheme(ColorScheme scheme) {
  final p = defaultTargetPlatform;
  final isWin = !kIsWeb && p == TargetPlatform.windows;
  final isLinux = !kIsWeb && p == TargetPlatform.linux;
  final radius = isWin ? 6.0 : (isLinux ? 12.0 : 16.0);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  final inputRadius = BorderRadius.circular(isWin ? 4 : (isLinux ? 10 : 12));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: isWin ? 'Segoe UI' : null,
    fontFamilyFallback: isLinux ? const ['Cantarell', 'Ubuntu', 'Noto Sans', 'DejaVu Sans'] : null,
    visualDensity: (isWin || isLinux) ? VisualDensity.compact : VisualDensity.standard,
    scaffoldBackgroundColor: scheme.surface,
    // Clear press and hover feedback on every button, card and list row.
    splashFactory: InkRipple.splashFactory,
    splashColor: scheme.primary.withValues(alpha: 0.14),
    highlightColor: scheme.primary.withValues(alpha: 0.08),
    hoverColor: scheme.primary.withValues(alpha: 0.06),
    focusColor: scheme.primary.withValues(alpha: 0.10),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      scrolledUnderElevation: isWin ? 0 : 2,
      centerTitle: false,
      titleSpacing: 16,
      toolbarHeight: 56,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerLow,
      // Soft blue outline, shared by every card so the app reads as one piece.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.primary.withValues(alpha: 0.22)),
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.onPrimaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      shape: const StadiumBorder(),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorColor: scheme.primary,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, isWin || isLinux ? 40 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        iconSize: 18,
        splashFactory: InkRipple.splashFactory,
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.45)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, isWin || isLinux ? 40 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        iconSize: 18,
        shape: isWin ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)) : null,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(0, isWin || isLinux ? 40 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        iconSize: 18,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size.square(isWin || isLinux ? 40 : 48),
        padding: EdgeInsets.zero,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    dialogTheme: DialogThemeData(shape: shape),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius * 0.75)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 24,
      horizontalTitleGap: 16,
      iconColor: scheme.onSurfaceVariant,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(extendedIconLabelSpacing: 10),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: inputRadius),
      isDense: isWin || isLinux,
    ),
    snackBarTheme: SnackBarThemeData(shape: shape),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      height: 68,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
