import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/app.dart';
import 'package:vaulton/core/providers.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/widgets/vaulton_logo.dart';

void main() {
  testWidgets('shows the sign-in screen with provider-backed app state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          sessionProvider.overrideWithValue(SessionStore()),
        ],
        child: const VaultonApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Sign In to Your Server'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('renders the shared Vaulton shield logo without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: VaultonLogo(size: 48))),
      ),
    );

    expect(find.byType(VaultonLogo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

