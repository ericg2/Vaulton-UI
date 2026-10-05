import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'background/background_api.dart';
import 'core/providers.dart';
import 'core/session.dart';
import 'platform/desktop_window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  await initDesktopWindow();
  try {
    await initBackground();
  } catch (e) {
    debugPrint('Background init failed: $e');
  }
  final prefs = await SharedPreferences.getInstance();
  final session = SessionStore();
  try {
    await session.load();
  } catch (e) {
    debugPrint('Secure storage unavailable: $e');
  }
  runApp(ProviderScope(
    retry: (count, error) => null,
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      sessionProvider.overrideWithValue(session),
    ],
    child: const VaultonApp(),
  ));
}
