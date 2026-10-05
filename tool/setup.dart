// One-shot project bootstrap:  dart run tool/setup.dart
//
// The android/ and web/ runners are part of the project and already configured
// (permissions, network security config, Gradle). This script only:
//   1. creates the Windows / Linux runners if they are missing, and
//   2. runs `flutter pub get` (which also writes android/local.properties).
import 'dart:io';

Future<void> main() async {
  Future<void> run(String exe, List<String> args) async {
    stdout.writeln('> $exe ${args.join(' ')}');
    final p = await Process.start(exe, args, mode: ProcessStartMode.inheritStdio, runInShell: Platform.isWindows);
    final code = await p.exitCode;
    if (code != 0) {
      stderr.writeln('Command failed ($code)');
      exit(code);
    }
  }

  if (!Directory('android').existsSync()) {
    stderr.writeln('android/ is missing. Restore it from the project archive: it holds the manifest permissions '
        '(INTERNET, media access), the network security config and the AGP 9 / Kotlin Gradle setup.');
    exit(1);
  }

  final missing = [for (final p in ['windows', 'linux']) if (!Directory(p).existsSync()) p];
  if (missing.isNotEmpty) {
    await run('flutter', ['create', '--platforms=${missing.join(',')}', '--project-name=vaulton', '--org=com.example', '.']);
  }

  await run('flutter', ['pub', 'get']);
  stdout.writeln('\nDone. Run:  flutter run -d windows | linux | chrome | <android-device>');
}
