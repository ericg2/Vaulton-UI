import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      final l = light?.harmonized() ?? ColorScheme.fromSeed(seedColor: seedColor);
      final d = dark?.harmonized() ?? ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
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
