import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import '../core/api_client.dart';
import '../core/session.dart';
import '../core/wake.dart';
import '../features/sync/sync_models.dart';
import '../features/sync/sync_service.dart';
import '../features/transfers/transfer_engine.dart';
import '../features/transfers/transfer_manager.dart';
import '../features/transfers/transfer_models.dart';

const _kSync = 'vaulton.sync.periodic';
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

Future<void> initBackground() async {
  if (backgroundSupported) await Workmanager().initialize(backgroundDispatcher);
}

Future<void> configureSyncSchedules(List<SyncProfile> profiles) async {
  if (!backgroundSupported) return;
  for (final p in profiles) {
    final unique = 'vaulton-sync-' + p.id;
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
