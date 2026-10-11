import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const _api = 'https://api.github.com/repos/ericg2/Vaulton-UI/releases/latest';
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(minutes: 3),
    headers: const {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Vaulton-Android',
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
      String? apkUrl;
      String? checksumUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String?;
        if (name == 'Vaulton-Android.apk') apkUrl = url;
        if (name == 'Vaulton-Android.apk.sha256') checksumUrl = url;
      }
      if (apkUrl == null || checksumUrl == null) {
        throw const FormatException('The latest release does not contain the APK and checksum assets.');
      }

      if (!context.mounted) return;
      final install = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Update Available'),
          content: Text('Vaulton $latestVersion is available. You are using $currentVersion. Download and install the update?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Update')),
          ],
        ),
      );
      if (install != true || !context.mounted) return;

      messenger.showSnackBar(const SnackBar(content: Text('Downloading Vaulton update…')));
      final checksumResponse = await _dio.get<String>(
        checksumUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final expectedHash = RegExp(r'^[0-9a-fA-F]{64}')
          .firstMatch(checksumResponse.data?.trim() ?? '')
          ?.group(0)
          ?.toLowerCase();
      if (expectedHash == null) throw const FormatException('The release checksum is invalid.');

      final apkResponse = await _dio.get<List<int>>(
        apkUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = apkResponse.data;
      if (bytes == null || bytes.isEmpty) throw const FormatException('The APK download was empty.');
      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != expectedHash) {
        throw const FormatException('The APK checksum did not match. The download was discarded.');
      }

      final directory = await getApplicationSupportDirectory();
      final apk = File(p.join(directory.path, 'Vaulton-update-$latestVersion.apk'));
      await apk.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      final result = await OpenFilex.open(
        apk.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done && context.mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Could not open the Android installer: ${result.message}'),
          duration: const Duration(seconds: 8),
        ));
      }
    } catch (error) {
      if (quietErrors || !context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Could not check or install updates: ${_friendlyError(error)}'),
        duration: const Duration(seconds: 8),
      ));
    }
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
