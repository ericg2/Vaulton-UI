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
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      scrolledUnderElevation: isWin ? 0 : 2,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: shape,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    dialogTheme: DialogThemeData(shape: shape),
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius * 0.75))),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: inputRadius),
      isDense: isWin || isLinux,
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: isWin ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)) : null)),
    snackBarTheme: SnackBarThemeData(shape: shape),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
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
