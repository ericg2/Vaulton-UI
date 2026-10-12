import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../background/background_api.dart';

class _UpdateProgress {
  const _UpdateProgress(this.message, {this.progress});

  final String message;
  final double? progress;
}

class UpdateService {
  static const _api = 'https://api.github.com/repos/ericg2/Vaulton-UI/releases/latest';
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
      if (!_isNewer(latestVersion, currentVersion)) {
        if (!quietIfUpToDate && context.mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('Vaulton is up to date.')));
        }
        return;
      }

      final assets = (release['assets'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final names = Platform.isAndroid
          ? ('Vaulton-Android.apk', 'Vaulton-Android.apk.sha256')
          : Platform.isWindows
              ? ('Vaulton-Windows-Setup.exe', 'Vaulton-Windows-Setup.exe.sha256')
              : Platform.isLinux
                  ? ('Vaulton-Linux.tar.gz', 'Vaulton-Linux.tar.gz.sha256')
                  : (null, null);
      if (names.$1 == null) {
        throw const FormatException('Automatic updates are not supported on this platform.');
      }

      String? packageUrl;
      String? checksumUrl;
      String? installerUrl;
      String? installerChecksumUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String?;
        if (name == names.$1) packageUrl = url;
        if (name == names.$2) checksumUrl = url;
        if (name == 'Vaulton-Linux-Install.sh') installerUrl = url;
        if (name == 'Vaulton-Linux-Install.sh.sha256') installerChecksumUrl = url;
      }
      if (packageUrl == null || checksumUrl == null) {
        throw const FormatException('The latest release is still being prepared or is missing its package/checksum.');
      }
      if (Platform.isLinux && (installerUrl == null || installerChecksumUrl == null)) {
        throw const FormatException('The latest release is missing the Linux update installer.');
      }

      if (!context.mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update Available'),
          content: Text(
            'Vaulton $latestVersion is ready to install. Your current version is $currentVersion. '
            'Continue to download and verify the update?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Update')),
          ],
        ),
      );
      if (install != true || !context.mounted) return;

      if (Platform.isAndroid) {
        final progress = ValueNotifier<_UpdateProgress>(const _UpdateProgress('Preparing background download…'));
        var dialogOpen = true;
        Timer? poller;
        unawaited(showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => ValueListenableBuilder<_UpdateProgress>(
            valueListenable: progress,
            builder: (context, value, _) => AlertDialog(
              title: const Text('Downloading Vaulton'),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.downloading_outlined, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text(value.message)),
                ]),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: value.progress, minHeight: 8),
                ),
                if (value.progress != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: Text('${(value.progress! * 100).round()}%')),
                ],
                const SizedBox(height: 8),
                Text('You can leave Vaulton while the download continues. A notification will show its progress.',
                  style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
        ));
        try {
          await startBackgroundUpdateDownload(
            packageUrl: packageUrl,
            checksumUrl: checksumUrl,
            fileName: names.$1!,
            version: latestVersion,
          );
          poller = Timer.periodic(const Duration(milliseconds: 600), (_) async {
            if (!context.mounted) {
              poller?.cancel();
              progress.dispose();
              return;
            }
            final state = await readBackgroundUpdateState();
            final status = state['status'] as String? ?? 'idle';
            final message = state['message'] as String? ?? 'Preparing download…';
            final rawProgress = state['progress'];
            final value = rawProgress is num ? rawProgress.toDouble() : null;
            progress.value = _UpdateProgress(message, progress: value);
            if (status == 'ready' || status == 'failed') {
              poller?.cancel();
              if (dialogOpen && context.mounted) {
                Navigator.of(context, rootNavigator: true).pop();
                dialogOpen = false;
              }
              progress.dispose();
              if (status == 'failed') {
                final error = state['error'] as String? ?? 'The background download failed.';
                if (context.mounted) messenger.showSnackBar(SnackBar(
                  content: Text('Update download failed: ${_friendlyError(FormatException(error))}'),
                  duration: const Duration(seconds: 10),
                  action: SnackBarAction(label: 'Retry', onPressed: () => checkAndInstall(context, currentVersion)),
                ));
                return;
              }
              final path = state['path'] as String?;
              if (path == null || !await File(path).exists()) {
                if (context.mounted) messenger.showSnackBar(const SnackBar(content: Text('The update finished, but its file could not be found. Please check for updates again.')));
                return;
              }
              if (context.mounted) {
                final result = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
                if (result.type != ResultType.done && context.mounted) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Download complete, but Android could not open the installer: ${result.message}'),
                    duration: const Duration(seconds: 10),
                  ));
                }
              }
            }
          });
        } catch (error) {
          poller?.cancel();
          if (dialogOpen && context.mounted) Navigator.of(context, rootNavigator: true).pop();
          progress.dispose();
          rethrow;
        }
        return;
      }

      final progress = ValueNotifier<_UpdateProgress>(
        const _UpdateProgress('Preparing the update…'),
      );
      var progressDialogOpen = true;
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ValueListenableBuilder<_UpdateProgress>(
          valueListenable: progress,
          builder: (context, value, _) => AlertDialog(
            title: const Text('Updating Vaulton'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value.message),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: value.progress),
                if (value.progress != null) ...[
                  const SizedBox(height: 8),
                  Text('${(value.progress! * 100).round()}%'),
                ],
              ],
            ),
          ),
        ),
      ));

      void setProgress(String message, {double? value}) {
        progress.value = _UpdateProgress(message, progress: value);
      }

      try {
        final directory = await getTemporaryDirectory();
        final package = await _downloadVerified(
          packageUrl,
          checksumUrl,
          p.join(directory.path, names.$1!),
          onProgress: (received, total) => setProgress(
            'Downloading Vaulton $latestVersion…',
            value: total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null,
          ),
          onStatus: (message) => setProgress(message),
        );
        if (!context.mounted) return;

        if (Platform.isAndroid) {
          setProgress('Download verified. Android will now ask you to confirm the installation.', value: 1);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (context.mounted && progressDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
            progressDialogOpen = false;
          }
          final result = await OpenFilex.open(
            package.path,
            type: 'application/vnd.android.package-archive',
          );
          if (result.type != ResultType.done && context.mounted) {
            messenger.showSnackBar(SnackBar(
              content: Text('Could not open the Android installer: ${result.message}'),
              duration: const Duration(seconds: 8),
            ));
          }
          return;
        }

        if (Platform.isWindows) {
          setProgress('Opening the Windows installer. Vaulton will close, then reopen when the update is complete.', value: 1);
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
          final helper = await _downloadVerified(
            installerUrl!,
            installerChecksumUrl!,
            p.join(directory.path, 'Vaulton-Linux-Install.sh'),
            onProgress: (received, total) => setProgress(
              'Downloading the Linux installer…',
              value: total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null,
            ),
            onStatus: (message) => setProgress(message),
          );
          setProgress('Starting the installer…', value: 1);
          await Process.start(
            'bash',
            [
              helper.path,
              '--update',
              '--pid',
              '$pid',
              '--archive',
              package.path,
              '--target',
              p.dirname(Platform.resolvedExecutable),
            ],
            mode: ProcessStartMode.detached,
          );
          exit(0);
        }
      } finally {
        if (progressDialogOpen && context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progress.dispose();
      }
    } catch (error) {
      if (quietErrors || !context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Update failed: ${_friendlyError(error)}'),
        duration: const Duration(seconds: 8),
      ));
    }
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
