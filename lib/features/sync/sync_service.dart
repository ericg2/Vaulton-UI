import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../transfers/transfer_engine.dart';
import 'sync_models.dart';
import 'sync_source.dart';

enum SyncChangeKind { add, update, delete, mkdir, replace }

class SyncChange {
  const SyncChange({required this.kind, required this.path, required this.bytes, this.source});
  final SyncChangeKind kind;
  final String path;
  final int bytes;
  final SyncSourceEntry? source;
}

class SyncPlan {
  SyncPlan(this.changes, {required this.sourceFiles, required this.destinationFiles});
  final List<SyncChange> changes;
  final int sourceFiles, destinationFiles;
  Iterable<SyncChange> get uploads => changes.where((x) =>
      x.kind == SyncChangeKind.add || x.kind == SyncChangeKind.update || x.kind == SyncChangeKind.replace);
  Iterable<SyncChange> get deletes => changes.where((x) => x.kind == SyncChangeKind.delete);
  Iterable<SyncChange> get directories => changes.where((x) =>
      x.kind == SyncChangeKind.mkdir || (x.kind == SyncChangeKind.replace && x.source?.isDir == true));
  int get newFiles => changes.where((x) => x.kind == SyncChangeKind.add).length;
  int get updatedFiles => changes.where((x) =>
      x.kind == SyncChangeKind.update || (x.kind == SyncChangeKind.replace && x.source?.isDir == false)).length;
  int get deletedFiles => deletes.length;
  int get uploadBytes => uploads.fold(0, (a, x) => a + x.bytes);
  int get deleteBytes => deletes.fold(0, (a, x) => a + x.bytes);
}

Future<SyncPlan> buildSyncPlan(ApiClient api, SyncProfile profile, SharedPreferences prefs,
    {void Function(SyncRunStatus)? onProgress}) async {
  final source = openSyncSource(SyncSourceInfo(
    kind: profile.sourceKind, location: profile.sourceLocation, label: profile.sourceLabel,
  ));
  final status = SyncRunStatus(
    running: true, phase: 'Scanning Source', startedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await status.save(prefs, profile.id);
  onProgress?.call(status);

  final local = await source.scan();
  status.scannedSource = local.length;
  status.phase = 'Scanning Destination';
  await status.save(prefs, profile.id);
  onProgress?.call(status);

  final remote = <SyncSourceEntry>[];
  final v = Vaulton(api);

  Future<void> walkRemote(String dir, String relBase) async {
    String? cursor;
    do {
      final page = await v.list(profile.pointId, dir, cursor: cursor, limit: 200, order: 'Asc');
      for (final n in page.items) {
        final rel = relBase.isEmpty ? n.name : relBase + '/' + n.name;
        remote.add(SyncSourceEntry(
          relative: rel,
          size: n.bytes,
          modified: n.modified ?? DateTime.fromMillisecondsSinceEpoch(0),
          isDir: n.isDir,
          location: joinPath(dir, n.name),
        ));
        if (n.isDir) await walkRemote(joinPath(dir, n.name), rel);
      }
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);
  }

  await walkRemote(profile.remoteDir, '');
  status.scannedDestination = remote.length;
  status.phase = 'Comparing';
  await status.save(prefs, profile.id);
  onProgress?.call(status);

  final localBy = {for (final e in local.where((e) => e.relative.isNotEmpty)) e.relative: e};
  final remoteBy = {for (final e in remote.where((e) => e.relative.isNotEmpty)) e.relative: e};
  final changes = <SyncChange>[];

  for (final e in localBy.values) {
    final r = remoteBy[e.relative];
    if (e.isDir) {
      if (r == null) {
        changes.add(SyncChange(kind: SyncChangeKind.mkdir, path: e.relative, bytes: 0, source: e));
      } else if (!r.isDir) {
        changes.add(SyncChange(kind: SyncChangeKind.replace, path: e.relative, bytes: 0, source: e));
      }
      continue;
    }
    if (r == null) {
      changes.add(SyncChange(kind: SyncChangeKind.add, path: e.relative, bytes: e.size, source: e));
    } else if (r.isDir) {
      changes.add(SyncChange(kind: SyncChangeKind.replace, path: e.relative, bytes: e.size, source: e));
    } else {
      final sameTime = (e.modified.millisecondsSinceEpoch - r.modified.millisecondsSinceEpoch).abs() <= 2000;
      if (e.size != r.size || !sameTime) {
        changes.add(SyncChange(kind: SyncChangeKind.update, path: e.relative, bytes: e.size, source: e));
      }
    }
  }

  if (profile.deleteExtras) {
    final sourcePaths = localBy.keys.toSet();
    final deleteRoots = <String>{};
    for (final r in remoteBy.values) {
      if (sourcePaths.contains(r.relative)) continue;
      final parts = r.relative.split('/');
      var prefix = '';
      var covered = false;
      for (var i = 0; i < parts.length - 1; i++) {
        prefix = prefix.isEmpty ? parts[i] : prefix + '/' + parts[i];
        if (deleteRoots.contains(prefix)) {
          covered = true;
          break;
        }
      }
      if (covered) continue;
      if (r.isDir) deleteRoots.add(r.relative);
      changes.add(SyncChange(kind: SyncChangeKind.delete, path: r.relative, bytes: r.size));
    }
  }

  final sourceFileCount = local.where((e) => !e.isDir).length;
  final plannedFileChanges = changes.where((x) =>
      x.kind == SyncChangeKind.add ||
      x.kind == SyncChangeKind.update ||
      (x.kind == SyncChangeKind.replace && x.source?.isDir == false)).length;

  status
    ..totalFiles = sourceFileCount
    ..totalBytes = local.where((e) => !e.isDir).fold(0, (a, e) => a + e.size)
    ..newFiles = changes.where((x) => x.kind == SyncChangeKind.add).length
    ..updatedFiles = changes.where((x) => x.kind == SyncChangeKind.update || x.kind == SyncChangeKind.replace).length
    ..deletedFiles = changes.where((x) => x.kind == SyncChangeKind.delete).length
    ..unchangedFiles = sourceFileCount - plannedFileChanges
    ..bytesTotal = changes.where((x) => x.kind != SyncChangeKind.delete && x.kind != SyncChangeKind.mkdir).fold(0, (a, x) => a + x.bytes)
    ..phase = 'Ready'
    ..running = false;

  await status.save(prefs, profile.id);
  onProgress?.call(status);
  return SyncPlan(changes, sourceFiles: local.length, destinationFiles: remote.length);
}

Future<void> applySyncPlan(ApiClient api, SyncProfile profile, SyncPlan plan, SharedPreferences prefs,
    {void Function(SyncRunStatus)? onProgress, CancelToken? cancel}) async {
  final source = openSyncSource(SyncSourceInfo(
    kind: profile.sourceKind, location: profile.sourceLocation, label: profile.sourceLabel,
  ));
  final v = Vaulton(api);
  final status = SyncRunStatus(
    running: true,
    phase: 'Preparing',
    startedAt: DateTime.now().millisecondsSinceEpoch,
    totalFiles: plan.sourceFiles,
    totalBytes: plan.uploadBytes,
    bytesTotal: plan.uploadBytes,
    newFiles: plan.newFiles,
    updatedFiles: plan.updatedFiles,
    deletedFiles: plan.deletedFiles,
  );
  await status.save(prefs, profile.id);
  onProgress?.call(status);

  final dirs = plan.directories.toList()
    ..sort((a, b) => a.path.split('/').length.compareTo(b.path.split('/').length));

  for (final x in dirs) {
    cancel?.throwIfCancelled();
    status.phase = 'Creating Folders';
    status.current = x.path;
    final remote = joinPath(profile.remoteDir, x.path);
    if (x.kind == SyncChangeKind.replace) await v.deleteEntry(profile.pointId, remote);
    await v.mkdir(profile.pointId, remote);
    status.completed++;
    await status.save(prefs, profile.id);
    onProgress?.call(status);
  }

  final actions = plan.changes.where((x) =>
      x.kind == SyncChangeKind.add ||
      x.kind == SyncChangeKind.update ||
      (x.kind == SyncChangeKind.replace && x.source?.isDir == false)).toList();

  for (final x in actions) {
    cancel?.throwIfCancelled();
    final src = x.source!;
    status.phase = x.kind == SyncChangeKind.add ? 'Uploading New Files' : 'Updating Files';
    status.current = x.path;
    final remote = joinPath(profile.remoteDir, x.path);
    if (x.kind == SyncChangeKind.replace) await v.deleteEntry(profile.pointId, remote);
    final stream = await source.openRead(src);
    final base = status.bytesDone;
    await TransferEngine(api).uploadStream(
      pointId: profile.pointId,
      remotePath: remote,
      stream: stream,
      size: src.size,
      overwrite: true,
      onProgress: (sent, _) {
        status.bytesDone = base + sent;
        onProgress?.call(status);
      },
      cancel: cancel,
    );
    status.bytesDone = base + src.size;
    status.completed++;
    await status.save(prefs, profile.id);
    onProgress?.call(status);
  }

  final deletes = plan.deletes.toList()
    ..sort((a, b) => b.path.split('/').length.compareTo(a.path.split('/').length));

  for (final x in deletes) {
    cancel?.throwIfCancelled();
    status.phase = 'Removing Destination Extras';
    status.current = x.path;
    await v.deleteEntry(profile.pointId, joinPath(profile.remoteDir, x.path));
    status.completed++;
    await status.save(prefs, profile.id);
    onProgress?.call(status);
  }

  status
    ..running = false
    ..phase = 'Complete'
    ..current = null
    ..message = 'Destination now matches the source.'
    ..finishedAt = DateTime.now().millisecondsSinceEpoch;
  await status.save(prefs, profile.id);
  onProgress?.call(status);
}

Future<void> runScheduledSync(ApiClient api, SharedPreferences prefs, SyncProfile profile) async {
  if (!profile.enabled) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (profile.nextRun > 0 && now < profile.nextRun) return;

  try {
    final plan = await buildSyncPlan(api, profile, prefs);
    await applySyncPlan(api, profile, plan, prefs);
    profile.lastRun = DateTime.now().millisecondsSinceEpoch;
    profile.nextRun = profile.lastRun + profile.intervalMinutes * 60000;
  } catch (e) {
    final status = SyncRunStatus(running: false, phase: 'Failed', error: e.toString(), finishedAt: now);
    await status.save(prefs, profile.id);
    profile.nextRun = now + profile.intervalMinutes * 60000;
  }

  final profiles = SyncProfile.loadAll(prefs);
  final i = profiles.indexWhere((x) => x.id == profile.id);
  if (i >= 0) {
    profiles[i]
      ..lastRun = profile.lastRun
      ..nextRun = profile.nextRun;
  }
  await SyncProfile.saveAll(prefs, profiles);
}
