import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _UpdateProgress {
  const _UpdateProgress(this.message, {this.progress, this.canInstall = false});

  final String message;
  final double? progress;
  final bool canInstall;
}

Widget _buildReleaseNotes(String markdown, ThemeData theme) {
  final spans = <TextSpan>[];
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  for (var index = 0; index < lines.length; index++) {
    var line = lines[index].trimRight();
    if (line.trim().isEmpty) {
      spans.add(const TextSpan(text: '\n'));
      continue;
    }
    final heading = RegExp(r'^\s{0,3}#{1,4}\s+(.+)$').firstMatch(line);
    TextStyle? lineStyle = theme.textTheme.bodySmall;
    if (heading != null) {
      line = heading.group(1)!;
      lineStyle = theme.textTheme.titleSmall;
    } else {
      final bullet = RegExp(r'^\s*[-*+]\s+(.+)$').firstMatch(line);
      if (bullet != null) line = '•  ${bullet.group(1)!}';
    }
    final inline = <TextSpan>[];
    final pattern = RegExp(r'\*\*([^*]+)\*\*|(?<!\*)\*([^*]+)\*(?!\*)|\[([^\]]+)\]\([^)]+\)');
    var offset = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > offset) inline.add(TextSpan(text: line.substring(offset, match.start)));
      if (match.group(1) != null) {
        inline.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (match.group(2) != null) {
        inline.add(TextSpan(text: match.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
      } else {
        inline.add(TextSpan(text: match.group(3), style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline)));
      }
      offset = match.end;
    }
    if (offset < line.length) inline.add(TextSpan(text: line.substring(offset)));
    spans.add(TextSpan(style: lineStyle, children: inline));
    if (index < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return SelectableText.rich(TextSpan(children: spans));
}

class UpdateService {
  static const _api = 'https://api.github.com/repos/ericg2/Vaulton-UI/releases/latest';
  static Future<FlutterLocalNotificationsPlugin>? _notificationInit;
  static DateTime _lastNotificationAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<FlutterLocalNotificationsPlugin> _notifier() => _notificationInit ??= () async {
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'vaulton_updates', 'Vaulton updates',
      description: 'Download and verification progress for Vaulton updates.', importance: Importance.low,
    ));
    return notifications;
  }();

  static Future<void> _notifyProgress(_UpdateProgress progress, {bool ongoing = true}) async {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (ongoing && now.difference(_lastNotificationAt) < const Duration(milliseconds: 650)) return;
    _lastNotificationAt = now;
    final notifications = await _notifier();
    final percent = progress.progress == null ? null : (progress.progress! * 100).round();
    await notifications.show(
      id: 7301,
      title: progress.message.toLowerCase().startsWith('downloading') ? 'Downloading Vaulton' : 'Vaulton update',
      body: percent == null ? progress.message : progress.message + ' (' + percent.toString() + '%)',
      notificationDetails: NotificationDetails(android: AndroidNotificationDetails(
        'vaulton_updates', 'Vaulton updates',
        channelDescription: 'Download and verification progress for Vaulton updates.',
        importance: Importance.low, priority: Priority.low, onlyAlertOnce: true,
        ongoing: ongoing, autoCancel: !ongoing, showProgress: true,
        maxProgress: 100, progress: percent ?? 0, indeterminate: percent == null,
      )),
    );
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 5),
    headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Vaulton',
    },
  ));

  static Future<void> checkAndInstall(
    BuildContext context,
    String currentVersion, {
    bool quietIfUpToDate = false,
    bool quietErrors = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await _dio.get<Map<String, dynamic>>(_api);
      final release = response.data;
      if (release == null) throw const FormatException('GitHub returned an empty release.');
      final tag = (release['tag_name'] as String? ?? '').trim();
      final latestVersion = tag.startsWith('v') ? tag.substring(1) : tag;
      final releaseNotes = (release['body'] as String? ?? '').trim();
      if (!_isNewer(latestVersion, currentVersion)) {
        if (!quietIfUpToDate && context.mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('Vaulton is up to date.')));
        }
        return;
      }

      final assets = (release['assets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      String? linuxPackage;
      if (Platform.isLinux && await _isLinuxPackageManaged()) {
        if (!quietIfUpToDate && context.mounted) {
          final command = _linuxPackageManagerCommand();
          messenger.showSnackBar(SnackBar(
            content: Text(command == null
                ? 'Update Vaulton through your configured Linux package repository.'
                : 'Update Vaulton with: $command'),
            duration: const Duration(seconds: 10),
          ));
        }
        return;
      }
      if (Platform.isLinux) {
        linuxPackage = _linuxPackageName(latestVersion);
        if (linuxPackage == null) {
          throw const FormatException('Automatic Linux updates are not available for this distribution.');
        }
      }

      String? packageName;
      String? checksumName;
      if (Platform.isAndroid) {
        packageName = 'vaulton-$latestVersion-android.apk';
        checksumName = '$packageName.sha256';
      } else if (Platform.isWindows) {
        packageName = 'vaulton-$latestVersion-windows-setup.exe';
        checksumName = '$packageName.sha256';
      } else if (Platform.isLinux) {
        packageName = linuxPackage;
        checksumName = '$packageName.sha256';
      }
      if (packageName == null) {
        throw const FormatException('Automatic updates are not supported on this platform.');
      }

      String? packageUrl;
      String? checksumUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String?;
        final legacyLinuxPackage = linuxPackage == null
            ? null
            : (linuxPackage.endsWith('.deb') ? 'Vaulton-Linux.deb' : 'Vaulton-Linux.rpm');
        if (name == packageName ||
            (Platform.isAndroid && name == 'Vaulton-Android.apk') ||
            (Platform.isWindows && name == 'Vaulton-Windows-Setup.exe') ||
            (Platform.isLinux && name == legacyLinuxPackage)) {
          packageUrl = url;
        }
        if (name == checksumName ||
            (Platform.isAndroid && name == 'Vaulton-Android.apk.sha256') ||
            (Platform.isWindows && name == 'Vaulton-Windows-Setup.exe.sha256') ||
            (Platform.isLinux && name == '$legacyLinuxPackage.sha256')) {
          checksumUrl = url;
        }
      }
      if (packageUrl == null || checksumUrl == null) {
        throw const FormatException('The latest release is still being prepared or is missing its package/checksum.');
      }

      if (!context.mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          final colors = theme.colorScheme;
          return AlertDialog(
            insetPadding: const EdgeInsets.all(16),
            title: const Text('Update Available'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vaulton $latestVersion', style: theme.textTheme.titleLarge),
                    Text(
                      'Installed version: $currentVersion',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      Platform.isLinux
                          ? 'Vaulton will download and verify the update, then open your package installer.'
                          : 'Vaulton will download and verify the update before opening the installer.',
                    ),
                    if (releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('What’s New', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      _buildReleaseNotes(releaseNotes, theme),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Later')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Install Update'),
              ),
            ],
          );
        },
      );
      if (install != true || !context.mounted) return;

      final progress = ValueNotifier<_UpdateProgress>(
        _UpdateProgress('Downloading Vaulton ' + latestVersion + '…'),
      );
      var progressDialogOpen = true;
      final installTrigger = Completer<bool>();
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ValueListenableBuilder<_UpdateProgress>(
          valueListenable: progress,
          builder: (context, value, _) => PopScope(
            canPop: value.canInstall,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop && !installTrigger.isCompleted) {
                installTrigger.complete(false);
                progressDialogOpen = false;
                unawaited(_notifyProgress(const _UpdateProgress('Installation postponed.'), ongoing: false).catchError((_) {}));
              }
            },
            child: AlertDialog(
              title: Text(value.canInstall ? 'Ready to Install' : 'Downloading Update'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value.message),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: value.progress),
                if (value.progress != null && !value.canInstall) ...[
                  const SizedBox(height: 8),
                  Text('${(value.progress! * 100).round()}%'),
                ],
              ],
              ),
              actions: [
                if (value.canInstall) ...[
                  TextButton(
                    onPressed: () {
                      if (!installTrigger.isCompleted) installTrigger.complete(false);
                      progressDialogOpen = false;
                      unawaited(_notifyProgress(const _UpdateProgress('Installation postponed.'), ongoing: false).catchError((_) {}));
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text('Later'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (!installTrigger.isCompleted) installTrigger.complete(true);
                      progressDialogOpen = false;
                      Navigator.of(dialogContext).pop();
                    },
                    icon: const Icon(Icons.install_desktop_outlined),
                    label: const Text('Install Now'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ));

      void setProgress(String message, {double? value, bool ongoing = true, bool canInstall = false}) {
        progress.value = _UpdateProgress(message, progress: value, canInstall: canInstall);
        unawaited(_notifyProgress(progress.value, ongoing: ongoing).catchError((_) {}));
      }

      try {
        final directory = await getTemporaryDirectory();
        final package = await _downloadVerified(
          packageUrl,
          checksumUrl,
          p.join(directory.path, packageName),
          onProgress: (received, total) => setProgress(
            'Downloading Vaulton $latestVersion…',
            value: total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null,
          ),
          onStatus: (message) => setProgress(message),
        );
        if (!context.mounted) return;
        setProgress('Download verified. Review the installer prompt to continue.', value: 1, ongoing: true, canInstall: true);
        final installRequested = await installTrigger.future;
        if (!installRequested || !context.mounted) return;

        if (Platform.isAndroid) {
          setProgress('Opening Android installation confirmation…', value: 1, ongoing: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          final result = await OpenFilex.open(
            package.path,
            type: 'application/vnd.android.package-archive',
          );
          if (result.type != ResultType.done && context.mounted) {
            await _notifyProgress(const _UpdateProgress('Could not open the Android installer.'), ongoing: false);
            messenger.showSnackBar(SnackBar(
              content: Text('Could not open the Android installer: ${result.message}'),
              duration: const Duration(seconds: 8),
            ));
          }
          return;
        }

        if (Platform.isWindows) {
          setProgress('Opening the Windows installer. Vaulton will close, then reopen when the update is complete.', value: 1, ongoing: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          final installDir = p.dirname(Platform.resolvedExecutable);
          await Process.start(
            package.path,
            [
              '/CLOSEAPPLICATIONS',
              '/RESTARTAPPLICATIONS',
              '/DIR="$installDir"',
            ],
            mode: ProcessStartMode.detached,
          );
          exit(0);
        }

        if (Platform.isLinux) {
          setProgress('Opening the package installer…', value: 1, ongoing: false);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          final opened = await _openWithDesktopInstaller(package.path);
          if (!opened) {
            if (context.mounted) {
              messenger.showSnackBar(SnackBar(
                content: Text('Install the downloaded package with your package manager: ${package.path}'),
                duration: const Duration(seconds: 10),
              ));
            }
            return;
          }
          // Close Vaulton so the package installer can replace the files.
          await Future<void>.delayed(const Duration(milliseconds: 800));
          exit(0);
        }
      } finally {
        if (progressDialogOpen && context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progress.dispose();
      }
    } catch (error) {
      if (Platform.isAndroid) {
        await _notifyProgress(_UpdateProgress('Update failed: ' + _friendlyError(error)), ongoing: false).catchError((_) {});
      }
      if (quietErrors || !context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Update failed: ${_friendlyError(error)}'),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  static Future<bool> _isLinuxPackageManaged() async {
    String? id;
    String? idLike;
    try {
      final release = File('/etc/os-release');
      if (!release.existsSync()) return false;
      for (final line in release.readAsLinesSync()) {
        if (line.startsWith('ID=')) id = line.substring(3).trim().replaceAll('"', '').toLowerCase();
        if (line.startsWith('ID_LIKE=')) idLike = line.substring(8).trim().replaceAll('"', '').toLowerCase();
      }
      final ids = '$id $idLike';
      if (ids.contains('debian') || ids.contains('ubuntu') || ids.contains('mint')) {
        final source = File('/etc/apt/sources.list.d/vaulton.sources');
        if (!source.existsSync() || !source.readAsStringSync().contains('ericg2.github.io/apt')) return false;
        final result = await Process.run('dpkg-query', ['-W', r'-f=${Status}', 'vaulton']);
        return result.exitCode == 0 && result.stdout.toString().trim() == 'install ok installed';
      }
      if (ids.contains('suse') || ids.contains('opensuse')) {
        final source = File('/etc/zypp/repos.d/vaulton.repo');
        if (!source.existsSync() || !source.readAsStringSync().contains('ericg2.github.io/rpm')) return false;
        final result = await Process.run('rpm', ['-q', 'vaulton']);
        return result.exitCode == 0;
      }
      if (ids.contains('rhel') || ids.contains('fedora') || ids.contains('centos')) {
        final source = File('/etc/yum.repos.d/vaulton.repo');
        if (!source.existsSync() || !source.readAsStringSync().contains('ericg2.github.io/rpm')) return false;
        final result = await Process.run('rpm', ['-q', 'vaulton']);
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static String? _linuxPackageName(String version) {
    String? id;
    String? idLike;
    try {
      final release = File('/etc/os-release');
      if (!release.existsSync()) return null;
      for (final line in release.readAsLinesSync()) {
        if (line.startsWith('ID=')) id = line.substring(3).trim().replaceAll('"', '').toLowerCase();
        if (line.startsWith('ID_LIKE=')) idLike = line.substring(8).trim().replaceAll('"', '').toLowerCase();
      }
    } catch (_) {
      return null;
    }
    final ids = '$id $idLike';
    if (ids.contains('debian') || ids.contains('ubuntu') || ids.contains('mint')) {
      return 'vaulton-$version-linux-amd64.deb';
    }
    if (ids.contains('rhel') || ids.contains('fedora') || ids.contains('suse') || ids.contains('opensuse') || ids.contains('centos')) {
      return 'vaulton-$version-linux-x86_64.rpm';
    }
    return null;
  }

  /// The Linux package that matches the running distribution.
  ///
  /// Debian and Ubuntu take a .deb; Fedora, RHEL and openSUSE take a .rpm.
  static String? _linuxPackageManagerCommand() {
    String? id;
    String? idLike;
    try {
      final release = File('/etc/os-release');
      if (!release.existsSync()) return null;
      for (final line in release.readAsLinesSync()) {
        if (line.startsWith('ID=')) id = line.substring(3).trim().replaceAll('"', '').toLowerCase();
        if (line.startsWith('ID_LIKE=')) idLike = line.substring(8).trim().replaceAll('"', '').toLowerCase();
      }
    } catch (_) {
      return null;
    }
    final ids = '$id $idLike';
    if (ids.contains('debian') || ids.contains('ubuntu') || ids.contains('mint')) {
      return 'sudo apt update && sudo apt install --only-upgrade vaulton';
    }
    if (ids.contains('suse') || ids.contains('opensuse')) {
      return 'sudo zypper refresh && sudo zypper update vaulton';
    }
    if (ids.contains('rhel') || ids.contains('fedora') || ids.contains('centos')) {
      return 'sudo dnf upgrade vaulton';
    }
    return null;
  }

  /// Hands the package to the desktop so the system installer can install it.
  static Future<bool> _openWithDesktopInstaller(String path) async {
    const openers = <(String, List<String>)>[
      ('xdg-open', <String>[]),
      ('gio', <String>['open']),
    ];
    for (final opener in openers) {
      try {
        final result = await Process.run(opener.$1, [...opener.$2, path]);
        if (result.exitCode == 0) return true;
      } catch (_) {
        // Try the next opener.
      }
    }
    return false;
  }

  static Future<File> _downloadVerified(
    String packageUrl,
    String checksumUrl,
    String outputPath, {
    void Function(int received, int total)? onProgress,
    void Function(String message)? onStatus,
  }) async {
    onStatus?.call('Checking the downloaded file…');
    final checksumResponse = await _dio.get<String>(
      checksumUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final expectedHash = RegExp(r'^[0-9a-fA-F]{64}')
        .firstMatch(checksumResponse.data?.trim() ?? '')
        ?.group(0)
        ?.toLowerCase();
    if (expectedHash == null) throw const FormatException('The release checksum is invalid.');

    final file = File(outputPath);
    if (await file.exists()) {
      onStatus?.call('Checking the saved download…');
      final existingBytes = await file.readAsBytes();
      if (existingBytes.isNotEmpty && sha256.convert(existingBytes).toString() == expectedHash) {
        onStatus?.call('Using the verified download already on this device.');
        return file;
      }
      await file.delete();
    }

    onStatus?.call('Downloading update…');
    final response = await _dio.get<List<int>>(
      packageUrl,
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgress,
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) throw const FormatException('The download was empty.');

    onStatus?.call('Verifying the download…');
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != expectedHash) {
      throw const FormatException('The SHA-256 checksum did not match. The download was discarded.');
    }

    await file.parent.create(recursive: true);
    final temporaryFile = File('$outputPath.part');
    await temporaryFile.writeAsBytes(bytes, flush: true);
    await temporaryFile.rename(outputPath);
    return file;
  }

  static bool _isNewer(String latest, String current) {
    final a = _versionParts(latest);
    final b = _versionParts(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int>? _versionParts(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) return null;
    return [int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!)];
  }

  static String _friendlyError(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 404) return 'No published release was found yet.';
      if (error.response?.statusCode == 403) return 'GitHub rate-limited the update check. Try again later.';
      return error.message ?? 'Network request failed.';
    }
    if (error is FormatException) return error.message;
    return error.toString();
  }
}
