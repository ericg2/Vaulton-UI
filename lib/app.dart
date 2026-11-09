import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'core/providers.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
import 'features/auth/splash_page.dart';
import 'features/settings/settings_page.dart' show kAppVersion;
import 'features/settings/update_service.dart';
import 'features/shell/shell.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class VaultonApp extends ConsumerWidget {
  const VaultonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return DynamicColorBuilder(builder: (light, dark) {
      final l = light == null ? ColorScheme.fromSeed(seedColor: seedColor) : _fromDynamicScheme(light);
      final d = dark == null ? ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark) : _fromDynamicScheme(dark);
      return MaterialApp(
        title: 'Vaulton',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(l),
        darkTheme: buildTheme(d),
        themeMode: mode,
        home: const AuthGate(),
      );
    });
  }
}

/// Chooses between splash / login / home and cross-fades between them so
/// screen changes never pop. Only the status is watched, so token refreshes or
/// profile updates do not rebuild the gate.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          UpdateService.checkAndInstall(
            context,
            kAppVersion,
            quietIfUpToDate: true,
            quietErrors: true,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authProvider.select((a) => a.status));
    final Widget child = switch (status) {
      AuthStatus.loading => const SplashPage(key: ValueKey('splash')),
      AuthStatus.signedOut => const LoginPage(key: ValueKey('login')),
      AuthStatus.signedIn => const HomeShell(key: ValueKey('home')),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(a), child: c),
      ),
      child: child,
    );
  }
}

/// Converts the `material_ui` scheme returned by `dynamic_color` 2.x into the
/// Flutter Material [ColorScheme] used by the rest of the app.
ColorScheme _fromDynamicScheme(mui.ColorScheme scheme) {
  final s = scheme.harmonized();
  return ColorScheme(
    brightness: s.brightness,
    primary: s.primary,
    onPrimary: s.onPrimary,
    primaryContainer: s.primaryContainer,
    onPrimaryContainer: s.onPrimaryContainer,
    primaryFixed: s.primaryFixed,
    primaryFixedDim: s.primaryFixedDim,
    onPrimaryFixed: s.onPrimaryFixed,
    onPrimaryFixedVariant: s.onPrimaryFixedVariant,
    secondary: s.secondary,
    onSecondary: s.onSecondary,
    secondaryContainer: s.secondaryContainer,
    onSecondaryContainer: s.onSecondaryContainer,
    secondaryFixed: s.secondaryFixed,
    secondaryFixedDim: s.secondaryFixedDim,
    onSecondaryFixed: s.onSecondaryFixed,
    onSecondaryFixedVariant: s.onSecondaryFixedVariant,
    tertiary: s.tertiary,
    onTertiary: s.onTertiary,
    tertiaryContainer: s.tertiaryContainer,
    onTertiaryContainer: s.onTertiaryContainer,
    tertiaryFixed: s.tertiaryFixed,
    tertiaryFixedDim: s.tertiaryFixedDim,
    onTertiaryFixed: s.onTertiaryFixed,
    onTertiaryFixedVariant: s.onTertiaryFixedVariant,
    error: s.error,
    onError: s.onError,
    errorContainer: s.errorContainer,
    onErrorContainer: s.onErrorContainer,
    surface: s.surface,
    onSurface: s.onSurface,
    surfaceDim: s.surfaceDim,
    surfaceBright: s.surfaceBright,
    surfaceContainerLowest: s.surfaceContainerLowest,
    surfaceContainerLow: s.surfaceContainerLow,
    surfaceContainer: s.surfaceContainer,
    surfaceContainerHigh: s.surfaceContainerHigh,
    surfaceContainerHighest: s.surfaceContainerHighest,
    onSurfaceVariant: s.onSurfaceVariant,
    outline: s.outline,
    outlineVariant: s.outlineVariant,
    shadow: s.shadow,
    scrim: s.scrim,
    inverseSurface: s.inverseSurface,
    onInverseSurface: s.onInverseSurface,
    inversePrimary: s.inversePrimary,
    surfaceTint: s.surfaceTint,
  );
}
