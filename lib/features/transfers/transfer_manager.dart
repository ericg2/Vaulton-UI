import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../background/background_api.dart';
import '../../core/api_client.dart';
import '../../core/providers.dart';
import 'transfer_engine.dart';
import 'transfer_models.dart';

const kQueueKey = 'transfers_v1';
const kUiHeartbeat = 'ui_hb';
const kBgHeartbeat = 'bg_drain_hb';

typedef _TransferKey = ({TKind kind, String pointId, String remotePath, String? snapshotId});

class UploadRequest {
  const UploadRequest({
    required this.pointId,
    required this.remotePath,
    required this.size,
    this.localPath,
    this.bytes,
    this.loadBytes,
    this.origin = 'manual',
    this.overwrite = false,
  });

  final String pointId, remotePath;
  final String? localPath;
  final Uint8List? bytes;
  final Future<Uint8List> Function()? loadBytes;
  final int size;
  final String origin;
  final bool overwrite;
}

String encodeQueue(List<TransferTask> tasks) {
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  return jsonEncode([for (final t in tasks) if (t.active || t.createdAt.isAfter(cutoff)) t.toJson()]);
}

List<TransferTask> decodeQueue(String? raw) {
  final out = <TransferTask>[];
  if (raw == null) return out;
  try {
    for (final j in jsonDecode(raw) as List) {
      out.add(TransferTask.fromJson(Map<String, dynamic>.from(j)));
    }
  } catch (_) {}
  return out;
}

/// Queue of uploads/downloads with concurrency, resume (downloads), automatic
/// retry and persistence. On Android, when the app is left, unfinished work is
/// handed to a WorkManager worker so it keeps going with the app closed.
class TransferManager extends Notifier<List<TransferTask>> {
  final List<TransferTask> _tasks = [];
  final Map<String, TransferTask> _taskById = {};
  final Queue<String> _pending = Queue<String>();
  final Map<String, CancelToken> _tokens = {};
  final Map<String, Uint8List> _webBytes = {};
  final Map<String, Future<Uint8List> Function()> _webLoaders = {};
  late final TransferEngine _engine;
  int _running = 0, _seq = 0;
  Timer? _flush, _persistTimer, _handoffTimer, _watch, _hb;
  bool _handedOff = false, _dirty = false;
  // Captured in build(): reading other providers is not allowed in onDispose.
  late final SharedPreferences _prefs;

  bool get hasActive => _tasks.any((t) => t.active);

  @override
  List<TransferTask> build() {
    _engine = TransferEngine(ref.read(apiClientProvider));
    _prefs = ref.read(prefsProvider);
    if (!kIsWeb) {
      for (final t in decodeQueue(_prefs.getString(kQueueKey))) {
        if (t.state == TState.running) t.state = TState.queued;
        _tasks.add(t);
        _taskById[t.id] = t;
        if (t.state == TState.queued) _pending.addLast(t.id);
      }
      _hb = Timer.periodic(const Duration(seconds: 5), (_) => _prefs.setInt(kUiHeartbeat, DateTime.now().millisecondsSinceEpoch));
    }
    ref.onDispose(() {
      _flush?.cancel();
      _persistTimer?.cancel();
      _hb?.cancel();
      _watch?.cancel();
      _handoffTimer?.cancel();
      _epochTimer?.cancel();
      _persist();
    });
    Future.microtask(_pump);
    return List.of(_tasks);
  }

  // ------------------------------------------------------------ public API
  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  bool _duplicate(TKind k, String point, String remote, [String? snapshot]) =>
      _tasks.any((t) => t.active && t.kind == k && t.pointId == point && t.remotePath == remote && t.snapshotId == snapshot);

  TransferTask? addUpload({
    required String pointId,
    required String remotePath,
    String? localPath,
    Uint8List? bytes,
    Future<Uint8List> Function()? loadBytes,
    required int size,
    String origin = 'manual',
    bool overwrite = false,
  }) {
    return addUploads([
      UploadRequest(
        pointId: pointId,
        remotePath: remotePath,
        localPath: localPath,
        bytes: bytes,
        loadBytes: loadBytes,
        size: size,
        origin: origin,
        overwrite: overwrite,
      ),
    ]).first;
  }

  /// Adds a large upload batch with one queue update and one persistence write.
  /// Web file bytes are loaded only when a task starts, bounding memory by transfer concurrency.
  List<TransferTask?> addUploads(Iterable<UploadRequest> requests) {
    final seen = <_TransferKey>{
      for (final t in _tasks.where((t) => t.active))
        (kind: t.kind, pointId: t.pointId, remotePath: t.remotePath, snapshotId: t.snapshotId),
    };
    final results = <TransferTask?>[];
    var added = false;

    for (final request in requests) {
      final key = (
        kind: TKind.upload,
        pointId: request.pointId,
        remotePath: request.remotePath,
        snapshotId: null,
      );
      if (!seen.add(key)) {
        results.add(null);
        continue;
      }

      final t = TransferTask(
        id: _id(),
        kind: TKind.upload,
        pointId: request.pointId,
        remotePath: request.remotePath,
        name: request.remotePath.split('/').last,
        localPath: request.localPath,
        total: request.size,
        origin: request.origin,
        overwrite: request.overwrite,
      );
      if (request.bytes != null) _webBytes[t.id] = request.bytes!;
      if (request.loadBytes != null) _webLoaders[t.id] = request.loadBytes!;
      _tasks.add(t);
      _taskById[t.id] = t;
      _pending.addLast(t.id);
      results.add(t);
      added = true;
    }

    if (added) {
      _changed(persist: true);
      _pump();
    }
    return results;
  }

  TransferTask? addDownload({
    required String pointId,
    required String remotePath,
    required String name,
    required String localPath,
    int size = 0,
    String? snapshotId,
  }) {
    if (_duplicate(TKind.download, pointId, remotePath, snapshotId)) return null;
    final t = TransferTask(
      id: _id(), kind: TKind.download, pointId: pointId, remotePath: remotePath, name: name, localPath: localPath,
      total: size, snapshotId: snapshotId, origin: snapshotId != null ? 'snapshot' : 'manual');
    _tasks.add(t);
    _taskById[t.id] = t;
    _pending.addLast(t.id);
    _changed(persist: true);
    _pump();
    return t;
  }

  void cancel(String id) {
    final t = _taskById[id];
    if (t == null) return;
    if (t.state == TState.running) {
      _tokens[id]?.cancel();
    } else if (t.active) {
      t.state = TState.canceled;
      _changed(persist: true);
    }
  }

  void cancelAll() {
    var changed = false;
    for (final t in _tasks.where((t) => t.active)) {
      if (t.state == TState.running) {
        _tokens[t.id]?.cancel();
      } else {
        t.state = TState.canceled;
        changed = true;
      }
    }
    if (changed) {
      _rebuildPendingQueue();
      _changed(persist: true);
    }
  }

  void retry(String id, {bool overwrite = false}) {
    final t = _taskById[id];
    if (t == null || t.active) return;
    t.state = TState.queued;
    t.error = null;
    t.completedAt = null;
    t.attempts = 0;
    if (overwrite) t.overwrite = true;
    if (t.kind == TKind.upload) t.done = 0;
    _pending.addLast(t.id);
    _changed(persist: true);
    _pump();
  }

  void remove(String id) {
    final t = _taskById[id];
    if (t == null) return;
    if (t.state == TState.running) {
      _tokens[id]?.cancel();
    } else if (t.active) {
      t.state = TState.canceled;
    }
    if (!t.active) {
      _tasks.remove(t);
      _taskById.remove(id);
      _webBytes.remove(id);
      _webLoaders.remove(id);
    }
    _changed(persist: true);
  }

  void clearFinished() {
    final removed = _tasks.where((t) => !t.active).toList();
    for (final t in removed) {
      _taskById.remove(t.id);
      _webBytes.remove(t.id);
      _webLoaders.remove(t.id);
    }
    _tasks.removeWhere((t) => !t.active);
    _rebuildPendingQueue();
    _changed(persist: true);
  }

  void clearForPoint(String pointId) {
    final ids = _tasks.where((t) => t.pointId == pointId).map((t) => t.id).toSet();
    for (final t in _tasks.where((t) => ids.contains(t.id) && t.active).toList()) {
      _tokens[t.id]?.cancel();
    }
    _tasks.removeWhere((t) => ids.contains(t.id));
    for (final id in ids) {
      _taskById.remove(id);
      _webBytes.remove(id);
      _webLoaders.remove(id);
    }
    _rebuildPendingQueue();
    _changed(persist: true);
  }

  void reset() {
    for (final t in _tasks.where((t) => t.state == TState.running)) {
      _tokens[t.id]?.cancel();
    }
    _tasks.clear();
    _taskById.clear();
    _pending.clear();
    _webBytes.clear();
    _webLoaders.clear();
    _changed(persist: true);
  }

  void _rebuildPendingQueue() {
    _pending.clear();
    for (final t in _tasks) {
      if (t.state == TState.queued) _pending.addLast(t.id);
    }
  }

  void _rebuildTaskIndex({bool queuePending = false}) {
    _taskById.clear();
    _pending.clear();
    for (final t in _tasks) {
      _taskById[t.id] = t;
      if (queuePending && t.state == TState.queued) _pending.addLast(t.id);
    }
  }

  // ------------------------------------------------------------- internals
  void _pump() {
    if (_handedOff) return;
    final max = ref.read(settingsProvider).concurrency;
    while (_running < max && _pending.isNotEmpty) {
      final id = _pending.removeFirst();
      final next = _taskById[id];
      if (next == null || next.state != TState.queued) continue;
      _run(next);
    }
  }

  bool _retryable(ApiException e) => e.status == null || e.status! >= 500 || e.status == 408 || e.status == 429;

  Future<void> _run(TransferTask t) async {
    _running++;
    t.state = TState.running;
    t.error = null;
    _changed(persistSoon: true);
    final token = CancelToken();
    _tokens[t.id] = token;
    try {
      // Use the first authoritative total reported by the transport. Some
      // adapters revise their estimate as headers/resume state settle; letting
      // every callback replace the denominator makes the bar jump backwards.
      var totalLocked = false;
      void prog(int a, int b) {
        t.done = a;
        if (b > 0 && !totalLocked) {
          t.total = b;
          totalLocked = true;
        }
        _changed();
      }

      if (t.kind == TKind.upload) {
        final loader = _webLoaders[t.id];
        final bytes = _webBytes[t.id] ?? (loader == null ? null : await loader());
        await _engine.upload(t, bytes: bytes, onProgress: prog, cancel: token);
      } else {
        await _engine.download(t, onProgress: prog, cancel: token);
      }
      t.state = TState.done;
      t.completedAt = DateTime.now();
      if (t.total > 0) t.done = t.total;
      _webBytes.remove(t.id);
      _webLoaders.remove(t.id);
      _scheduleEpochBump();
    } on ApiException catch (e) {
      if (token.isCancelled) {
        t.state = _handedOff ? TState.queued : TState.canceled;
      } else if (_retryable(e) && ++t.attempts < 4) {
        if (t.kind == TKind.upload) t.done = 0;
        t.state = TState.queued;
        t.error = 'Retrying: ${e.message}';
        await Future.delayed(Duration(seconds: 2 * t.attempts * t.attempts));
        if (_taskById.containsKey(t.id)) _pending.addLast(t.id);
      } else {
        t.state = TState.failed;
        t.error = e.message;
      }
    } catch (e) {
      t.state = TState.failed;
      t.error = '$e';
    } finally {
      _tokens.remove(t.id);
      _running--;
      _changed(persistSoon: true);
      _pump();
    }
  }

  /// Tells dashboards / storage lists that server-side data changed. Debounced so
  /// a batch of uploads finishing together triggers a single reload.
  Timer? _epochTimer;
  void _scheduleEpochBump() {
    _epochTimer?.cancel();
    _epochTimer = Timer(const Duration(milliseconds: 800), () {
      try {
        ref.read(epochProvider.notifier).bump();
      } catch (_) {}
    });
  }

  void _changed({bool persist = false, bool persistSoon = false}) {
    if (persist) {
      _persistTimer?.cancel();
      _persistTimer = null;
      _persist();
      _flush?.cancel();
      _flush = null;
      _dirty = false;
      state = List.of(_tasks);
      return;
    }

    if (persistSoon && !kIsWeb) {
      _persistTimer ??= Timer(const Duration(milliseconds: 750), () {
        _persistTimer = null;
        _persist();
      });
    }

    _dirty = true;
    _flush ??= Timer(const Duration(milliseconds: 250), () {
      _flush = null;
      if (_dirty) {
        _dirty = false;
        state = List.of(_tasks);
      }
    });
  }

  void _persist() {
    if (kIsWeb) return;
    _prefs.setString(kQueueKey, encodeQueue(_tasks));
  }

  // ------------------------------------------------- background hand-off
  /// Wire this to the app lifecycle. Only does anything on Android.
  void onLifecycle(AppLifecycleState s) {
    if (!backgroundSupported) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _handoffTimer ??= Timer(const Duration(seconds: 20), _handOff);
    } else if (s == AppLifecycleState.resumed) {
      _handoffTimer?.cancel();
      _handoffTimer = null;
      if (_handedOff) _watchBackground();
    }
  }

  Future<void> _handOff() async {
    _handoffTimer = null;
    if (!hasActive) return;
    _handedOff = true;
    for (final tk in _tokens.values) {
      tk.cancel();
    }
    await Future.delayed(const Duration(milliseconds: 600));
    for (final t in _tasks) {
      if (t.state == TState.running) t.state = TState.queued;
    }
    _persistTimer?.cancel();
    _persistTimer = null;
    _persist();
    await scheduleDrain();
  }

  void _watchBackground() {
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _prefs.reload();
      final hb = _prefs.getInt(kBgHeartbeat) ?? 0;
      final fresh = DateTime.now().millisecondsSinceEpoch - hb < 25000;
      final loaded = decodeQueue(_prefs.getString(kQueueKey));
      if (fresh) {
        _tasks
          ..clear()
          ..addAll(loaded);
        _rebuildTaskIndex();
        state = List.of(_tasks);
      } else {
        _watch?.cancel();
        _tasks
          ..clear()
          ..addAll(loaded);
        for (final t in _tasks) {
          if (t.state == TState.running) t.state = TState.queued;
        }
        _rebuildTaskIndex(queuePending: true);
        _handedOff = false;
        state = List.of(_tasks);
        _pump();
      }
    });
  }
}

final transferProvider = NotifierProvider<TransferManager, List<TransferTask>>(TransferManager.new);
