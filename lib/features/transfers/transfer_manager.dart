import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
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
  final Map<String, CancelToken> _tokens = {};
  final Map<String, Uint8List> _webBytes = {};
  late final TransferEngine _engine;
  int _running = 0, _seq = 0;
  Timer? _flush, _handoffTimer, _watch, _hb;
  bool _handedOff = false, _dirty = false;

  bool get hasActive => _tasks.any((t) => t.active);

  @override
  List<TransferTask> build() {
    _engine = TransferEngine(ref.read(apiClientProvider));
    if (!kIsWeb) {
      for (final t in decodeQueue(ref.read(prefsProvider).getString(kQueueKey))) {
        if (t.state == TState.running) t.state = TState.queued;
        _tasks.add(t);
      }
      _hb = Timer.periodic(const Duration(seconds: 5), (_) => ref.read(prefsProvider).setInt(kUiHeartbeat, DateTime.now().millisecondsSinceEpoch));
    }
    ref.onDispose(() {
      _flush?.cancel();
      _hb?.cancel();
      _watch?.cancel();
      _handoffTimer?.cancel();
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
    required int size,
    String origin = 'manual',
    bool overwrite = false,
  }) {
    if (_duplicate(TKind.upload, pointId, remotePath)) return null;
    final t = TransferTask(
      id: _id(), kind: TKind.upload, pointId: pointId, remotePath: remotePath,
      name: remotePath.split('/').last, localPath: localPath, total: size, origin: origin, overwrite: overwrite);
    if (bytes != null) _webBytes[t.id] = bytes;
    _tasks.add(t);
    _changed(persist: true);
    _pump();
    return t;
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
    _changed(persist: true);
    _pump();
    return t;
  }

  void cancel(String id) {
    final t = _tasks.where((t) => t.id == id).firstOrNull;
    if (t == null) return;
    if (t.state == TState.running) {
      _tokens[id]?.cancel();
    } else if (t.active) {
      t.state = TState.canceled;
      _changed(persist: true);
    }
  }

  void cancelAll() {
    for (final t in _tasks.where((t) => t.active).toList()) {
      cancel(t.id);
    }
  }

  void retry(String id, {bool overwrite = false}) {
    final t = _tasks.where((t) => t.id == id).firstOrNull;
    if (t == null || t.active) return;
    t.state = TState.queued;
    t.error = null;
    t.attempts = 0;
    if (overwrite) t.overwrite = true;
    if (t.kind == TKind.upload) t.done = 0;
    _changed(persist: true);
    _pump();
  }

  void remove(String id) {
    cancel(id);
    _tasks.removeWhere((t) => t.id == id && !t.active);
    _webBytes.remove(id);
    _changed(persist: true);
  }

  void clearFinished() {
    _tasks.removeWhere((t) => !t.active);
    _changed(persist: true);
  }

  void reset() {
    cancelAll();
    _tasks.clear();
    _changed(persist: true);
  }

  // ------------------------------------------------------------- internals
  void _pump() {
    if (_handedOff) return;
    final max = ref.read(settingsProvider).concurrency;
    while (_running < max) {
      final next = _tasks.where((t) => t.state == TState.queued).firstOrNull;
      if (next == null) break;
      _run(next);
    }
  }

  bool _retryable(ApiException e) => e.status == null || e.status! >= 500 || e.status == 408 || e.status == 429;

  Future<void> _run(TransferTask t) async {
    _running++;
    t.state = TState.running;
    t.error = null;
    _changed(persist: true);
    final token = CancelToken();
    _tokens[t.id] = token;
    try {
      void prog(int a, int b) {
        t.done = a;
        if (b > 0) t.total = b;
        _changed();
      }

      if (t.kind == TKind.upload) {
        await _engine.upload(t, bytes: _webBytes[t.id], onProgress: prog, cancel: token);
      } else {
        await _engine.download(t, onProgress: prog, cancel: token);
      }
      t.state = TState.done;
      if (t.total > 0) t.done = t.total;
      _webBytes.remove(t.id);
    } on ApiException catch (e) {
      if (token.isCancelled) {
        t.state = _handedOff ? TState.queued : TState.canceled;
      } else if (_retryable(e) && ++t.attempts < 4) {
        t.state = TState.queued;
        t.error = 'Retrying: ${e.message}';
        await Future.delayed(Duration(seconds: 2 * t.attempts * t.attempts));
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
      _changed(persist: true);
      _pump();
    }
  }

  void _changed({bool persist = false}) {
    if (persist) {
      _persist();
      state = List.of(_tasks);
      return;
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
    ref.read(prefsProvider).setString(kQueueKey, encodeQueue(_tasks));
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
    _persist();
    await scheduleDrain();
  }

  void _watchBackground() {
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(seconds: 2), (_) async {
      final p = ref.read(prefsProvider);
      await p.reload();
      final hb = p.getInt(kBgHeartbeat) ?? 0;
      final fresh = DateTime.now().millisecondsSinceEpoch - hb < 25000;
      final loaded = decodeQueue(p.getString(kQueueKey));
      if (fresh) {
        _tasks
          ..clear()
          ..addAll(loaded);
        state = List.of(_tasks);
      } else {
        _watch?.cancel();
        _tasks
          ..clear()
          ..addAll(loaded);
        _handedOff = false;
        state = List.of(_tasks);
        _pump();
      }
    });
  }
}

final transferProvider = NotifierProvider<TransferManager, List<TransferTask>>(TransferManager.new);
