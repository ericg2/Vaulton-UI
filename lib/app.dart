import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'core/theme.dart';
import 'features/auth/login_page.dart';
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

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return switch (auth.status) {
      AuthStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.signedOut => const LoginPage(),
      AuthStatus.signedIn => const HomeShell(),
    };
  }
}
