import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/wake.dart';
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
  SyncPlan(this.changes, {required this.sourceFiles, required this.destinationFiles, required this.sourceEntries, this.sourceHashes = const {}, this.skipReason});
  final List<SyncChange> changes;
  final int sourceFiles, destinationFiles;
  final List<SyncSourceEntry> sourceEntries;
  final Map<String, String> sourceHashes;
  final String? skipReason;
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

Future<void> _recordSyncFailure(
  SharedPreferences prefs,
  SyncProfile profile,
  Object error, {
  void Function(SyncRunStatus)? onProgress,
}) async {
  final raw = error.toString();
  final cancelled = (error is DioException && CancelToken.isCancel(error)) || raw.toLowerCase().contains('sync cancelled');
  final lower = raw.toLowerCase();
  final sourceMissing = lower.contains('source folder is no longer available') ||
      lower.contains('source folder is unavailable');
  final destinationMissing = lower.contains('404') ||
      lower.contains('not found') ||
      lower.contains('does not exist') ||
      lower.contains('no such file or directory');
  final status = SyncRunStatus(
    running: false,
    phase: cancelled ? 'Cancelled' : 'Failed',
    error: cancelled ? null : sourceMissing
        ? 'Source folder is unavailable.'
        : destinationMissing
            ? 'Destination folder or data folder is unavailable. $raw'
            : raw,
    message: cancelled
        ? 'Sync cancelled.'
        : sourceMissing
        ? 'Sync paused. Choose the source folder again to resume.'
        : destinationMissing
            ? 'Check the selected destination data folder and remote path, then run sync again.'
            : 'Sync failed. Review the error details and try again.',
    finishedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await status.save(prefs, profile.id);
  onProgress?.call(status);
}

Future<SyncPlan> buildSyncPlan(
  ApiClient api,
  SyncProfile profile,
  SharedPreferences prefs, {
  void Function(SyncRunStatus)? onProgress,
  CancelToken? cancel,
  Future<String?> Function(bool hasLocalChanges)? gate,
}) async {
  try {
    return await _buildSyncPlan(api, profile, prefs, onProgress: onProgress, cancel: cancel, gate: gate);
  } catch (error) {
    await _recordSyncFailure(prefs, profile, error, onProgress: onProgress);
    rethrow;
  }
}

Future<SyncPlan> _buildSyncPlan(ApiClient api, SyncProfile profile, SharedPreferences prefs,
    {void Function(SyncRunStatus)? onProgress, CancelToken? cancel, Future<String?> Function(bool)? gate}) async {
  final source = openSyncSource(SyncSourceInfo(
    kind: profile.sourceKind, location: profile.sourceLocation, label: profile.sourceLabel,
  ));
  final status = SyncRunStatus(
    running: true, phase: 'Scanning Source', startedAt: DateTime.now().millisecondsSinceEpoch,
  );
  await status.save(prefs, profile.id);
  onProgress?.call(status);

  final manifest = loadSyncManifest(prefs, profile.id);
  var scanned = 0;
  var scannedDirectories = 0;
  var progressSave = Future<void>.value();
  final local = await source.scan(
    cancel: cancel,
    onDirectory: (relative) {
      scannedDirectories++;
      status.current = relative.isEmpty ? profile.sourceLabel : relative;
      if (scannedDirectories == 1 || scannedDirectories % 8 == 0) {
        onProgress?.call(status);
      }
    },
    onEntry: (entry) {
      scanned++;
      status.scannedSource = scanned;
      status.current = entry.relative;
      if (scanned == 1 || scanned % 8 == 0) {
        onProgress?.call(status);
        progressSave = progressSave.then((_) async { await status.save(prefs, profile.id); });
      }
    },
  );
  await progressSave;
  _throwIfCancelled(cancel);
  status.scannedSource = local.length;
  status.current = null;
  final sourceHashes = <String, String>{};

  // Decide from local state alone whether anything could need syncing, so an
  // idle schedule never has to touch (or wake) the server.
  final localFiles = {for (final e in local) if (!e.isDir && e.relative.isNotEmpty) e.relative: e};
  final localChanged = localFiles.values.any((e) {
    final prev = manifest[e.relative];
    return prev == null || !_sameMeta(prev, e);
  });
  final localRemoved = profile.deleteExtras && manifest.keys.any((k) => !localFiles.containsKey(k));
  if (gate != null) {
    final skip = await gate(localChanged || localRemoved);
    if (skip != null) {
      final done = SyncRunStatus(
        running: false,
        phase: 'Complete',
        message: skip,
        totalFiles: localFiles.length,
        unchangedFiles: localFiles.length,
        scannedSource: local.length,
        startedAt: status.startedAt,
        finishedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await done.save(prefs, profile.id);
      onProgress?.call(done);
      return SyncPlan(const [], sourceFiles: local.length, destinationFiles: 0, sourceEntries: local, skipReason: skip);
    }
  }
  _throwIfCancelled(cancel);
  status.scannedSource = local.length;
  status.current = null;
  status.phase = 'Scanning Destination';
  await status.save(prefs, profile.id);
  onProgress?.call(status);

  final remote = <SyncSourceEntry>[];
  final v = Vaulton(api);

  Future<void> validateDestinationRoot() async {
    _throwIfCancelled(cancel);
    var current = '/';
    final parts = profile.remoteDir.split('/').where((part) => part.isNotEmpty);
    for (final part in parts) {
      String? cursor = '';
      var found = false;
      do {
        _throwIfCancelled(cancel);
        final page = await v.list(profile.pointId, current, cursor: cursor, limit: 200, order: 'Asc');
        for (final node in page.items) {
          if (node.name == part && node.isDir) {
            found = true;
            break;
          }
        }
        cursor = found || !page.hasMore ? null : page.nextCursor;
      } while (cursor != null);
      if (!found) {
        throw Exception('Destination folder "$current$part" does not exist in the selected data folder.');
      }
      current = joinPath(current, part);
    }
    if (profile.remoteDir == '/') {
      await v.list(profile.pointId, '/', limit: 1, order: 'Asc');
    }
  }

  Future<void> walkRemote(String dir, String relBase) async {
    _throwIfCancelled(cancel);
    String? cursor;
    do {
      _throwIfCancelled(cancel);
      final page = await v.list(profile.pointId, dir, cursor: cursor, limit: 200, order: 'Asc');
      for (final n in page.items) {
        _throwIfCancelled(cancel);
        final rel = relBase.isEmpty ? n.name : '$relBase/${n.name}';
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

  await validateDestinationRoot();
  await walkRemote(profile.remoteDir, '');
  _throwIfCancelled(cancel);
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
      // Trust the manifest of what we last uploaded; with no record yet, adopt
      // the remote copy when the sizes agree instead of re-uploading it.
      final previous = manifest[e.relative];
      final sourceUnchanged = previous != null ? _sameMeta(previous, e) : r.size == e.size;
      if (!sourceUnchanged) {
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
        prefix = prefix.isEmpty ? parts[i] : '$prefix/${parts[i]}';
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
  return SyncPlan(changes, sourceFiles: local.length, destinationFiles: remote.length, sourceEntries: local, sourceHashes: sourceHashes);
}

Future<void> applySyncPlan(
  ApiClient api,
  SyncProfile profile,
  SyncPlan plan,
  SharedPreferences prefs, {
  void Function(SyncRunStatus)? onProgress,
  CancelToken? cancel,
}) async {
  try {
    await _applySyncPlan(api, profile, plan, prefs, onProgress: onProgress, cancel: cancel);
  } catch (error) {
    await _recordSyncFailure(prefs, profile, error, onProgress: onProgress);
    rethrow;
  }
}

Future<void> _applySyncPlan(ApiClient api, SyncProfile profile, SyncPlan plan, SharedPreferences prefs,
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

  // Always create the configured destination root, even when the source is empty.
  if (profile.remoteDir != '/') {
    await v.mkdir(profile.pointId, profile.remoteDir);
  }

  final dirs = plan.directories.toList()
    ..sort((a, b) => a.path.split('/').length.compareTo(b.path.split('/').length));

  for (final x in dirs) {
    _throwIfCancelled(cancel);
    status.phase = 'Creating Folders';
    status.current = x.path;
    final remote = joinPath(profile.remoteDir, x.path);
    if (x.kind == SyncChangeKind.replace) await v.deleteEntry(profile.pointId, remote);
    await v.mkdir(profile.pointId, remote);
    status.completed++;
    await status.save(prefs, profile.id);
    onProgress?.call(status);
  }

  final manifest = loadSyncManifest(prefs, profile.id);
  final changedPaths = {for (final x in plan.changes) x.path};
  // Files verified unchanged are recorded up front so an interrupted run
  // never has to re-check them.
  for (final entry in plan.sourceEntries.where((e) => !e.isDir && !changedPaths.contains(e.relative))) {
    manifest[entry.relative] = SyncManifestEntry(size: entry.size, modified: entry.modified.millisecondsSinceEpoch);
  }
  var lastManifestSave = DateTime.now();
  var lastStatusSave = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> flushManifest({bool force = false}) async {
    if (!force && DateTime.now().difference(lastManifestSave) < const Duration(seconds: 3)) return;
    lastManifestSave = DateTime.now();
    await saveSyncManifest(prefs, profile.id, manifest);
  }
  Future<void> flushStatus({bool force = false}) async {
    onProgress?.call(status);
    if (!force && DateTime.now().difference(lastStatusSave) < const Duration(milliseconds: 750)) return;
    lastStatusSave = DateTime.now();
    await status.save(prefs, profile.id);
  }
  await saveSyncManifest(prefs, profile.id, manifest);

  final actions = plan.changes.where((x) =>
      x.kind == SyncChangeKind.add ||
      x.kind == SyncChangeKind.update ||
      (x.kind == SyncChangeKind.replace && x.source?.isDir == false)).toList();

  try {
    var next = 0;
    Object? failure;
    Future<void> worker() async {
      while (failure == null) {
        _throwIfCancelled(cancel);
        final i = next++;
        if (i >= actions.length) return;
        final x = actions[i];
        try {
          final src = x.source!;
          status.phase = x.kind == SyncChangeKind.add ? 'Uploading New Files' : 'Updating Files';
          status.current = x.path;
          final remote = joinPath(profile.remoteDir, x.path);
          if (x.kind == SyncChangeKind.replace) await v.deleteEntry(profile.pointId, remote);
          final stream = await source.openRead(src);
          var sentSoFar = 0;
          await TransferEngine(api).uploadStream(
            pointId: profile.pointId,
            remotePath: remote,
            stream: stream,
            size: src.size,
            overwrite: true,
            onProgress: (sent, _) {
              // Retries can report a lower count; keep each file monotonic.
              if (sent > sentSoFar) {
                status.bytesDone += sent - sentSoFar;
                sentSoFar = sent;
              }
              onProgress?.call(status);
            },
            cancel: cancel,
          );
          if (src.size > sentSoFar) status.bytesDone += src.size - sentSoFar;
          manifest[x.path] = SyncManifestEntry(size: src.size, modified: src.modified.millisecondsSinceEpoch);
          status.completed++;
          await flushManifest();
          await flushStatus();
        } catch (e) {
          failure ??= e;
          rethrow;
        }
      }
    }

    await Future.wait(List.generate(actions.length < 3 ? actions.length : 3, (_) => worker()));
    if (failure != null) throw failure!;
  } finally {
    // Persist whatever finished, even on failure or cancel.
    await saveSyncManifest(prefs, profile.id, manifest);
  }

  final deletes = plan.deletes.toList()
    ..sort((a, b) => b.path.split('/').length.compareTo(a.path.split('/').length));

  for (final x in deletes) {
    _throwIfCancelled(cancel);
    status.phase = 'Removing Destination Extras';
    status.current = x.path;
    await v.deleteEntry(profile.pointId, joinPath(profile.remoteDir, x.path));
    status.completed++;
    await status.save(prefs, profile.id);
    onProgress?.call(status);
  }

  manifest.removeWhere((k, _) => !plan.sourceEntries.any((e) => e.relative == k && !e.isDir));
  await saveSyncManifest(prefs, profile.id, manifest);

  status
    ..running = false
    ..phase = 'Complete'
    ..current = null
    ..message = 'Destination now matches the source.'
    ..finishedAt = DateTime.now().millisecondsSinceEpoch;
  await status.save(prefs, profile.id);
  onProgress?.call(status);
}

bool _sameMeta(SyncManifestEntry prev, SyncSourceEntry e) {
  if (prev.size != e.size) return false;
  final m = e.modified.millisecondsSinceEpoch;
  // Some SAF providers report 0 or second-truncated times; treat those leniently.
  if (prev.modified == 0 || m == 0) return true;
  return (prev.modified - m).abs() < 2000;
}

void _throwIfCancelled(CancelToken? cancel) {
  if (cancel?.isCancelled == true) {
    throw DioException(requestOptions: RequestOptions(path: ''), type: DioExceptionType.cancel);
  }
}

Future<int> calculateNextSyncRun(
  ApiClient api,
  SyncProfile profile, {
  int fallbackDelayMs = 3600000,
}) async {
  try {
    final occurrences = await Vaulton(api).previewCron(
      profile.cron,
      tz: profile.timeZone,
      count: 1,
    );
    if (occurrences.isNotEmpty) return occurrences.first.millisecondsSinceEpoch;
  } catch (_) {}
  return DateTime.now().millisecondsSinceEpoch + fallbackDelayMs;
}

Future<void> runScheduledSync(ApiClient api, SharedPreferences prefs, SyncProfile profile,
    {void Function(SyncRunStatus)? onProgress, bool force = false}) async {
  if (!profile.enabled && !force) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (!force && profile.nextRun > 0 && now < profile.nextRun) return;

  // Syncs for one profile must never overlap: both runs mutate the same destination.
  final previous = SyncRunStatus.load(prefs, profile.id);
  if (previous.running && previous.startedAt > 0 &&
      now - previous.startedAt < const Duration(hours: 3).inMilliseconds) {
    profile.nextRun = profile.skipIfRunning
        ? await calculateNextSyncRun(api, profile)
        : now + const Duration(minutes: 1).inMilliseconds;
    final profiles = SyncProfile.loadAll(prefs);
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      profiles[index].nextRun = profile.nextRun;
      await SyncProfile.saveAll(prefs, profiles);
    }
    return;
  }

  try {
    final plan = await buildSyncPlan(api, profile, prefs, onProgress: onProgress, gate: (hasChanges) async {
      if (!hasChanges) return 'No changes since last sync.';
      if (await WakeService.ensureReady(api, allowWake: false)) return null;
      if (!profile.wakeServer) return 'Server is asleep and waking is turned off for this sync. Skipped.';
      if (await WakeService.ensureReady(api)) return null;
      throw ApiException('Vaulton server could not be reached or woken.');
    });
    if (plan.skipReason == null) {
      await applySyncPlan(api, profile, plan, prefs, onProgress: onProgress);
      profile.lastRun = DateTime.now().millisecondsSinceEpoch;
    } else if (plan.skipReason == 'No changes since last sync.') {
      profile.lastRun = DateTime.now().millisecondsSinceEpoch;
    }
    profile.nextRun = await calculateNextSyncRun(api, profile);
  } catch (e) {
    final error = e.toString();
    final lower = error.toLowerCase();
    final sourceMissing = lower.contains('source folder is no longer available') ||
        lower.contains('source folder is unavailable');
    final destinationMissing = lower.contains('404') ||
        lower.contains('not found') ||
        lower.contains('does not exist') ||
        lower.contains('no such file or directory');
    final status = SyncRunStatus(
      running: false,
      phase: 'Failed',
      error: sourceMissing
          ? 'Source folder is unavailable.'
          : destinationMissing
              ? 'Destination folder or data folder is unavailable. $error'
              : error,
      message: sourceMissing
          ? 'Sync paused. Choose the source folder again to resume.'
          : destinationMissing
              ? 'Check the selected destination data folder and remote path, then run sync again.'
              : 'Sync failed. Review the error details and try again.',
      finishedAt: now,
    );
    await status.save(prefs, profile.id);
    profile.enabled = profile.enabled && !sourceMissing;
    profile.nextRun = await calculateNextSyncRun(api, profile);
  }

  final profiles = SyncProfile.loadAll(prefs);
  final i = profiles.indexWhere((x) => x.id == profile.id);
  if (i >= 0) {
    profiles[i]
      ..enabled = profile.enabled
      ..lastRun = profile.lastRun
      ..nextRun = profile.nextRun;
  }
  await SyncProfile.saveAll(prefs, profiles);
}
