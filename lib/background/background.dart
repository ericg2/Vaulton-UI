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
const _kScheduledSyncIds = 'vaulton.sync.scheduled_ids';
const _kDrain = 'vaulton.drain';
const _kSyncChannel = 'vaulton_sync';

int _syncNotificationId(String id) => 7302 + (id.hashCode & 0x3fffffff);

const _kCancelAction = 'cancel_sync';

/// Handles taps on the notification's Cancel button, also while the app is closed.
@pragma('vm:entry-point')
void syncNotificationResponse(NotificationResponse response) {
  if (response.actionId == _kCancelAction && response.payload != null) {
    unawaited(cancelSyncNow(response.payload!));
  }
}

Future<FlutterLocalNotificationsPlugin> _syncNotifier() async {
  final n = FlutterLocalNotificationsPlugin();
  await n.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: syncNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: syncNotificationResponse,
  );
  await n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
    const AndroidNotificationChannel(_kSyncChannel, 'Folder sync',
        description: 'Progress and results of folder syncs.', importance: Importance.low),
  );
  return n;
}

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024.0;
  var i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${u[i]}';
}

Future<void> _showSyncProgress(FlutterLocalNotificationsPlugin n, SyncProfile profile, SyncRunStatus s,
    {bool cancelAction = false}) async {
  final total = s.bytesTotal;
  final percent = total > 0 ? (s.bytesDone * 100 / total).floor().clamp(0, 100) : null;
  final lines = <String>[];
  if (s.phase == 'Scanning Source') {
    lines.add('Scanning source · ${s.scannedSource} items');
  } else if (s.phase == 'Scanning Destination') {
    lines.add('Scanning destination · ${s.scannedDestination} items');
  } else if (total > 0) {
    lines.add('${s.phase} · ${_fmtBytes(s.bytesDone)} of ${_fmtBytes(total)}');
  } else {
    lines.add(s.phase);
  }
  if (s.current != null && s.current!.isNotEmpty) lines.add(s.current!);
  await n.show(
    id: _syncNotificationId(profile.id),
    title: percent == null ? 'Syncing ${profile.name}' : 'Syncing ${profile.name} · $percent%',
    body: lines.first,
    payload: profile.id,
    notificationDetails: NotificationDetails(android: AndroidNotificationDetails(
      _kSyncChannel, 'Folder sync',
      channelDescription: 'Progress and results of folder syncs.',
      importance: Importance.low, priority: Priority.low, onlyAlertOnce: true,
      ongoing: true, showProgress: true, maxProgress: 100,
      progress: percent ?? 0, indeterminate: percent == null,
      styleInformation: BigTextStyleInformation(lines.join('\n')),
      actions: cancelAction
          ? const [AndroidNotificationAction(_kCancelAction, 'Cancel', cancelNotification: false, showsUserInterface: false)]
          : null,
    )),
  );
}

/// Ongoing + result notifications for a sync, usable from both the background
/// worker and user-initiated runs inside the app.
class SyncNotification {
  SyncNotification._(this._n, this._profile, [this._cancelAction = false]);
  final FlutterLocalNotificationsPlugin? _n;
  final SyncProfile _profile;
  final bool _cancelAction;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// [cancelAction] adds a Cancel button; only valid for runs hosted by the background worker.
  static Future<SyncNotification> start(SyncProfile profile, {bool cancelAction = false}) async {
    if (!backgroundSupported) return SyncNotification._(null, profile);
    try {
      final n = await _syncNotifier();
      final x = SyncNotification._(n, profile, cancelAction);
      await _showSyncProgress(n, profile, SyncRunStatus(running: true, phase: 'Starting'), cancelAction: cancelAction);
      return x;
    } catch (_) {
      return SyncNotification._(null, profile);
    }
  }

  void progress(SyncRunStatus s) {
    final n = _n;
    if (n == null) return;
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(seconds: 1)) return;
    _last = now;
    unawaited(_showSyncProgress(n, _profile, s, cancelAction: _cancelAction).catchError((_) {}));
  }

  /// Removes the ongoing notification and posts a result if there is one worth showing.
  Future<void> finish(SharedPreferences prefs, {bool cancelled = false}) async {
    final n = _n;
    if (n == null) return;
    try {
      await n.cancel(id: _syncNotificationId(_profile.id));
      if (cancelled) return;
      final result = SyncRunStatus.load(prefs, _profile.id);
      final changed = result.newFiles + result.updatedFiles + result.deletedFiles;
      String? title, body;
      if (result.error != null) {
        title = 'Sync failed: ${_profile.name}';
        body = result.message ?? result.error;
      } else if (result.completed > 0 || changed > 0) {
        title = 'Sync complete: ${_profile.name}';
        body = '${result.newFiles} new, ${result.updatedFiles} updated, ${result.deletedFiles} removed.';
      } else if (result.message != null && result.message!.contains('Skipped')) {
        title = 'Sync skipped: ${_profile.name}';
        body = result.message;
      }
      if (title != null) {
        await n.show(
          id: _syncNotificationId(_profile.id) + 1,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(
            _kSyncChannel, 'Folder sync', importance: Importance.defaultImportance, priority: Priority.defaultPriority,
          )),
        );
      }
    } catch (_) {}
  }
}

Future<void> _runSyncWithNotification(ApiClient api, SharedPreferences prefs, SyncProfile profile, {bool force = false}) async {
  final note = await SyncNotification.start(profile, cancelAction: true);
  try {
    await runScheduledSync(api, prefs, profile, onProgress: note.progress, force: force);
  } finally {
    await note.finish(prefs);
  }
}

Future<void> startBackgroundUpdateDownload({required String packageUrl, required String checksumUrl, required String fileName, required String version}) async {
  if (!backgroundSupported) throw StateError('Background updates are only supported on Android.');
  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
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
          final profiles = SyncProfile.loadAll(prefs);
          final profileId = input?['profileId'] as String?;
          // Old installations may still have an unscoped periodic job queued.
          // Never let a legacy worker fan out and start every profile concurrently.
          if (profileId == null) return true;
          final selected = profiles.where((profile) => profile.id == profileId).toList();
          for (final profile in selected) {
            await _runSyncWithNotification(api, prefs, profile, force: input?['scheduled'] != true);
            if (input?['scheduled'] == true) {
              final updated = SyncProfile.loadAll(prefs)
                  .where((item) => item.id == profile.id)
                  .firstOrNull;
              if (updated != null) await _scheduleSyncOccurrence(updated, append: true);
            }
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
  await notifications.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(channel);
  Future<void> report(String message, {int? percent, bool ongoing = true}) async {
    await prefs.setString(_updateMessageKey, message);
    if (percent != null) await prefs.setDouble(_updateProgressKey, percent / 100);
    await notifications.show(id: 7301, title: 'Vaulton update', body: percent == null ? message : '$message ($percent%)',
      notificationDetails: NotificationDetails(android: AndroidNotificationDetails(channel.id, channel.name,
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
    await report('Download verified. Open Vaulton to install.', percent: 100, ongoing: false);
    return true;
  } catch (error) {
    await prefs.setString(_updateStatusKey, 'failed');
    await prefs.setString(_updateErrorKey, error.toString());
    await report('Update download failed. Open Vaulton to retry.', ongoing: false);
    return true;
  }
}

Future<void> initBackground() async {
  if (backgroundSupported) await Workmanager().initialize(backgroundDispatcher);
}

Future<void> configureSyncSchedules(List<SyncProfile> profiles) async {
  if (!backgroundSupported) return;
  final prefs = await SharedPreferences.getInstance();
  final currentIds = profiles.map((profile) => profile.id).toSet();
  final previousIds = prefs.getStringList(_kScheduledSyncIds) ?? const <String>[];
  for (final id in previousIds.where((id) => !currentIds.contains(id))) {
    await Workmanager().cancelByUniqueName('vaulton-sync-' + id);
    await Workmanager().cancelByUniqueName('vaulton-sync-now-' + id);
  }
  await prefs.setStringList(_kScheduledSyncIds, currentIds.toList());

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final androidNotifications = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidNotifications?.requestNotificationsPermission();
  await androidNotifications?.createNotificationChannel(const AndroidNotificationChannel(
    _kSyncChannel, 'Folder sync',
    description: 'Progress and results of folder syncs.', importance: Importance.low));

  for (final profile in profiles) {
    final unique = 'vaulton-sync-' + profile.id;
    await Workmanager().cancelByUniqueName(unique);
    if (!profile.enabled) {
      await Workmanager().cancelByUniqueName('vaulton-sync-now-' + profile.id);
      continue;
    }
    await _scheduleSyncOccurrence(profile);
  }
}

Future<void> _scheduleSyncOccurrence(SyncProfile profile, {bool append = false}) async {
  if (!backgroundSupported || !profile.enabled) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final delayMs = profile.nextRun > now ? profile.nextRun - now : 0;
  await Workmanager().registerOneOffTask(
    'vaulton-sync-' + profile.id,
    _kSync,
    initialDelay: Duration(milliseconds: delayMs),
    inputData: {'profileId': profile.id, 'scheduled': true},
    existingWorkPolicy: append ? ExistingWorkPolicy.update : ExistingWorkPolicy.replace,
    constraints: Constraints(
      networkType: profile.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      requiresCharging: profile.chargingOnly,
      requiresBatteryNotLow: true,
    ),
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
    foregroundServiceConfig: ForegroundServiceConfig(
      notificationTitle: 'Vaulton folder sync',
      notificationText: 'A scheduled folder sync is running.',
      notificationChannelId: 'vaulton_sync',
      notificationChannelName: 'Folder sync',
      notificationId: 7302 + (profile.id.hashCode & 0x3fffffff),
      foregroundServiceType: ForegroundServiceType.dataSync,
    ),
  );
}

/// Runs a user-requested sync in the background worker (foreground service),
/// so it keeps going after the app is closed.
Future<void> triggerSyncNow({String? profileId}) async {
  if (!backgroundSupported) return;
  final prefs = await SharedPreferences.getInstance();
  final profiles = SyncProfile.loadAll(prefs);
  final selected = profiles.where((profile) => profileId == null ? profile.enabled : profile.id == profileId);
  for (final profile in selected) {
    await SyncRunStatus(
      phase: 'Queued',
      message: 'Waiting for the background worker to start.',
      startedAt: 0,
    ).save(prefs, profile.id);
    await Workmanager().registerOneOffTask(
      'vaulton-sync-now-${profile.id}',
      _kSync,
      inputData: {'profileId': profile.id},
      existingWorkPolicy: ExistingWorkPolicy.replace,
      // The user asked for this run explicitly, so ignore Wi-Fi/charging limits.
      constraints: Constraints(networkType: NetworkType.connected),
      outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
      foregroundServiceConfig: ForegroundServiceConfig(
        notificationTitle: 'Vaulton folder sync',
        notificationText: 'A folder sync is running.',
        notificationChannelId: _kSyncChannel,
        notificationChannelName: 'Folder sync',
        notificationId: _syncNotificationId(profile.id),
        foregroundServiceType: ForegroundServiceType.dataSync,
      ),
    );
  }
}

Future<void> cancelSyncNow(String profileId) async {
  if (!backgroundSupported) return;
  final prefs = await SharedPreferences.getInstance();
  await Workmanager().cancelByUniqueName('vaulton-sync-now-$profileId');
  await Workmanager().cancelByUniqueName('vaulton-sync-$profileId');
  await SyncRunStatus(
    phase: 'Cancelled',
    message: 'Sync cancelled.',
    finishedAt: DateTime.now().millisecondsSinceEpoch,
  ).save(prefs, profileId);
  final profile = SyncProfile.loadAll(prefs).where((p) => p.id == profileId).firstOrNull;
  if (profile != null) {
    final n = FlutterLocalNotificationsPlugin();
    await n.cancel(id: _syncNotificationId(profileId));
    await _scheduleSyncOccurrence(profile);
  }
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
