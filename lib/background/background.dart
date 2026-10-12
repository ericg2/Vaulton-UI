import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../features/sync/sync_models.dart';
import '../features/sync/sync_service.dart';
import '../features/transfers/transfer_engine.dart';
import '../features/transfers/transfer_manager.dart';
import '../features/transfers/transfer_models.dart';

const _kSync = 'vaulton.sync.periodic';
const _kDrain = 'vaulton.drain';
const _kUpdateDownload = 'vaulton.update.download';
const _updateStatusKey = 'vaulton.update.status';
const _updatePathKey = 'vaulton.update.path';
const _updateMessageKey = 'vaulton.update.message';
const _updateProgressKey = 'vaulton.update.progress';
const _updateVersionKey = 'vaulton.update.version';
const _updateErrorKey = 'vaulton.update.error';

Future<void> startBackgroundUpdateDownload({required String packageUrl, required String checksumUrl, required String fileName, required String version}) async {
  if (!backgroundSupported) throw StateError('Background updates are only supported on Android.');
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_updateStatusKey, 'downloading');
  await prefs.setString(_updateMessageKey, 'Starting download…');
  await prefs.setDouble(_updateProgressKey, 0);
  await prefs.remove(_updateErrorKey);
  await prefs.setString(_updateVersionKey, version);
  await Workmanager().registerOneOffTask('vaulton-update-download', _kUpdateDownload,
    inputData: {'url': packageUrl, 'checksum': checksumUrl, 'fileName': fileName, 'version': version},
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest);
}

Future<Map<String, Object?>> readBackgroundUpdateState() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return {'status': prefs.getString(_updateStatusKey) ?? 'idle', 'path': prefs.getString(_updatePathKey),
    'message': prefs.getString(_updateMessageKey) ?? 'Preparing download…',
    'progress': prefs.getDouble(_updateProgressKey), 'version': prefs.getString(_updateVersionKey),
    'error': prefs.getString(_updateErrorKey)};
}
bool get backgroundSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (task == _kUpdateDownload) return await _runUpdateDownload(input, prefs);
      final session = SessionStore();
      await session.load();
      if (!session.isSignedIn) return true;
      final api = ApiClient(session);
      switch (task) {
        case _kSync:
          for (final p in SyncProfile.loadAll(prefs)) {
            await runScheduledSync(api, prefs, p);
          }
          return true;
        case _kDrain:
          final more = await _drain(api, prefs);
          if (more) await scheduleDrain();
          return true;
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> _drainProgress(SharedPreferences prefs, List<TransferTask> tasks) async {
  await prefs.setString(kQueueKey, encodeQueue(tasks));
  await prefs.setInt(kBgHeartbeat, DateTime.now().millisecondsSinceEpoch);
}

Future<bool> _drain(ApiClient api, SharedPreferences prefs) async {
  final ui = prefs.getInt(kUiHeartbeat) ?? 0;
  if (DateTime.now().millisecondsSinceEpoch - ui < 15000) return false;
  final tasks = decodeQueue(prefs.getString(kQueueKey));
  final engine = TransferEngine(api);
  final started = DateTime.now();

  Future<void> runOne(TransferTask t) async {
    t.state = TState.running;
    try {
      void prog(int a, int b) {
        t.done = a;
        if (b > 0) t.total = b;
        _drainProgress(prefs, tasks);
      }
      if (t.kind == TKind.upload) {
        await engine.upload(t, onProgress: prog);
      } else {
        await engine.download(t, onProgress: prog);
      }
      t.state = TState.done;
      t.completedAt = DateTime.now();
      if (t.total > 0) t.done = t.total;
    } on ApiException catch (e) {
      final retry = (e.status == null || e.status! >= 500) && ++t.attempts < 4;
      t.state = retry ? TState.queued : TState.failed;
      t.error = e.message;
    } catch (e) {
      t.state = TState.failed;
      t.error = e.toString();
    }
    await _drainProgress(prefs, tasks);
  }

  const budget = Duration(minutes: 9);
  while (DateTime.now().difference(started) < budget) {
    final batch = tasks.where((t) => t.state == TState.queued).take(2).toList();
    if (batch.isEmpty) break;
    await Future.wait(batch.map(runOne));
  }
  await _drainProgress(prefs, tasks);
  final more = tasks.any((t) => t.state == TState.queued);
  await prefs.setInt(kBgHeartbeat, 0);
  return more;
}


Future<bool> _runUpdateDownload(Map<String, dynamic>? input, SharedPreferences prefs) async {
  final notifications = FlutterLocalNotificationsPlugin();
  const channel = AndroidNotificationChannel('vaulton_updates', 'Vaulton updates',
    description: 'Download and verification progress for Vaulton updates.', importance: Importance.low);
  await notifications.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(channel);
  Future<void> report(String message, {int? percent, bool ongoing = true}) async {
    await prefs.setString(_updateMessageKey, message);
    if (percent != null) await prefs.setDouble(_updateProgressKey, percent / 100);
    await notifications.show(7301, 'Vaulton update', percent == null ? message : '$message ($percent%)',
      NotificationDetails(android: AndroidNotificationDetails(channel.id, channel.name,
        channelDescription: channel.description, importance: Importance.low, priority: Priority.low,
        onlyAlertOnce: true, ongoing: ongoing, showProgress: true, maxProgress: 100,
        progress: percent ?? 0, indeterminate: percent == null)));
  }
  try {
    final url = input?['url'] as String?;
    final checksumUrl = input?['checksum'] as String?;
    final fileName = input?['fileName'] as String?;
    final version = input?['version'] as String? ?? '';
    if (url == null || checksumUrl == null || fileName == null) throw const FormatException('The update download request was incomplete.');
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(minutes: 8),
      headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Vaulton'}));
    await report('Checking release checksum…');
    final checksumResponse = await dio.get<String>(checksumUrl, options: Options(responseType: ResponseType.plain));
    final expected = RegExp(r'^[0-9a-fA-F]{64}').firstMatch(checksumResponse.data?.trim() ?? '')?.group(0)?.toLowerCase();
    if (expected == null) throw const FormatException('The release checksum is invalid.');
    final directory = await getTemporaryDirectory();
    final file = File(p.join(directory.path, fileName));
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();
    await report('Downloading Vaulton $version…', percent: 0);
    var lastReported = DateTime.fromMillisecondsSinceEpoch(0);
    final response = await dio.download(url, partial.path, deleteOnError: true, onReceiveProgress: (received, total) {
      if (total <= 0) return;
      final now = DateTime.now();
      if (now.difference(lastReported) < const Duration(milliseconds: 350) && received < total) return;
      lastReported = now;
      final percent = (received * 100 / total).floor().clamp(0, 100);
      unawaited(report('Downloading Vaulton $version…', percent: percent));
    });
    if (response.statusCode == null || response.statusCode! < 200 || response.statusCode! >= 300) throw const FormatException('The update download did not complete successfully.');
    final bytes = await partial.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('The download was empty.');
    await report('Verifying update…');
    if (sha256.convert(bytes).toString() != expected) {
      await partial.delete();
      throw const FormatException('The SHA-256 checksum did not match. The download was discarded.');
    }
    if (await file.exists()) await file.delete();
    await partial.rename(file.path);
    await prefs.setString(_updatePathKey, file.path);
    await prefs.setString(_updateStatusKey, 'ready');
    await report('Download verified. Return to Vaulton to install.', percent: 100, ongoing: false);
    return true;
  } catch (error) {
    await prefs.setString(_updateStatusKey, 'failed');
    await prefs.setString(_updateErrorKey, error.toString());
    await report('Update download failed. Open Vaulton to retry.', ongoing: false);
    return false;
  }
}

Future<void> initBackground() async {
  if (backgroundSupported) await Workmanager().initialize(backgroundDispatcher);
}

Future<void> configureSyncSchedules(List<SyncProfile> profiles) async {
  if (!backgroundSupported) return;
  for (final p in profiles) {
    final unique = 'vaulton-sync-${p.id}';
    if (!p.enabled) {
      await Workmanager().cancelByUniqueName(unique);
      continue;
    }
    await Workmanager().registerPeriodicTask(
      unique,
      _kSync,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: p.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
        requiresCharging: p.chargingOnly,
        requiresBatteryNotLow: true,
      ),
    );
  }
}

Future<void> triggerSyncNow() async {
  if (!backgroundSupported) return;
  await Workmanager().registerOneOffTask(
    'vaulton-sync-now',
    _kSync,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
  );
}

Future<void> scheduleDrain() async {
  if (!backgroundSupported) return;
  await Workmanager().registerOneOffTask(
    'transfer-drain',
    _kDrain,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
  );
}
