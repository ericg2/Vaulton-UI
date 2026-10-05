import 'dart:async';
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

const _kPeriodic = 'vaulton.photo.periodic';
const _kSyncNow = 'vaulton.photo.now';
const _kDrain = 'vaulton.drain';

bool get backgroundSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final session = SessionStore();
      await session.load();
      if (!session.isSignedIn) return true;
      final api = ApiClient(session);
      switch (task) {
        case _kPeriodic:
        case _kSyncNow:
          if (!SyncSettings.load(prefs).enabled && task == _kPeriodic) return true;
          final more = await PhotoSyncService(api, prefs).run();
          if (more) await _enqueueSyncContinuation();
          return true;
        case _kDrain:
          final more = await _drain(api, prefs);
          if (more) await scheduleDrain();
          return true;
      }
      return true;
    } catch (_) {
      return false; // WorkManager retries with back-off
    }
  });
}

Future<void> _enqueueSyncContinuation() => Workmanager().registerOneOffTask(
      'photo-sync-continue', _kSyncNow,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay: const Duration(seconds: 15),
    );

/// Drains the persisted transfer queue while the UI is not running.
Future<bool> _drain(ApiClient api, SharedPreferences prefs) async {
  final ui = prefs.getInt(kUiHeartbeat) ?? 0;
  if (DateTime.now().millisecondsSinceEpoch - ui < 15000) return false; // UI is alive and handling it
  final tasks = decodeQueue(prefs.getString(kQueueKey));
  final engine = TransferEngine(api);
  final started = DateTime.now();
  var lastWrite = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> write({bool force = false}) async {
    final now = DateTime.now();
    if (!force && now.difference(lastWrite) < const Duration(seconds: 2)) return;
    lastWrite = now;
    await prefs.setString(kQueueKey, encodeQueue(tasks));
    await prefs.setInt(kBgHeartbeat, now.millisecondsSinceEpoch);
  }

  Future<void> runOne(TransferTask t) async {
    t.state = TState.running;
    try {
      void prog(int a, int b) {
        t.done = a;
        if (b > 0) t.total = b;
        write();
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
      t.error = '$e';
    }
    await write(force: true);
  }

  await write(force: true);
  const budget = Duration(minutes: 9);
  while (DateTime.now().difference(started) < budget) {
    final batch = tasks.where((t) => t.state == TState.queued).take(2).toList();
    if (batch.isEmpty) break;
    await Future.wait(batch.map(runOne));
  }
  await write(force: true);
  final remaining = tasks.any((t) => t.state == TState.queued);
  await prefs.setInt(kBgHeartbeat, 0);
  return remaining;
}

Future<void> initBackground() async {
  if (!backgroundSupported) return;
  await Workmanager().initialize(backgroundDispatcher);
}

Future<void> scheduleDrain() async {
  if (!backgroundSupported) return;
  await Workmanager().registerOneOffTask(
    'transfer-drain', _kDrain,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
  );
}

Future<void> configurePhotoSync(SyncSettings s) async {
  if (!backgroundSupported) return;
  if (!s.enabled) {
    await Workmanager().cancelByUniqueName('photo-sync');
    return;
  }
  await Workmanager().registerPeriodicTask(
    'photo-sync', _kPeriodic,
    frequency: Duration(minutes: s.intervalMinutes < 15 ? 15 : s.intervalMinutes),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(
      networkType: s.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
      requiresCharging: s.chargingOnly,
      requiresBatteryNotLow: true,
    ),
    backoffPolicy: BackoffPolicy.exponential,
  );
}

Future<void> triggerPhotoSyncNow() async {
  if (!backgroundSupported) return;
  await Workmanager().registerOneOffTask(
    'photo-sync-now', _kSyncNow,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    constraints: Constraints(networkType: NetworkType.connected),
    outOfQuotaPolicy: OutOfQuotaPolicy.runAsNonExpeditedWorkRequest,
  );
}
