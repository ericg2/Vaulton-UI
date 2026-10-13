import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:saf/saf.dart';

class SyncSourceInfo {
  const SyncSourceInfo({required this.kind, required this.location, required this.label});
  final String kind, location, label;
}
class SyncSourceEntry {
  const SyncSourceEntry({required this.relative, required this.size, required this.modified, required this.isDir, required this.location});
  final String relative, location;
  final int size;
  final DateTime modified;
  final bool isDir;
}
abstract class SyncSource {
  Future<List<SyncSourceEntry>> scan({CancelToken? cancel, void Function(SyncSourceEntry)? onEntry, void Function(String relative)? onDirectory});
  Future<Stream<List<int>>> openRead(SyncSourceEntry entry);
  Future<void> delete(SyncSourceEntry entry);
}
class _PathSource implements SyncSource {
  _PathSource(this.root);
  final String root;
  @override
  Future<List<SyncSourceEntry>> scan({CancelToken? cancel, void Function(SyncSourceEntry)? onEntry, void Function(String relative)? onDirectory}) async {
    final out = <SyncSourceEntry>[];
    final dir = Directory(root);
    if (!await dir.exists()) throw Exception('Source folder is no longer available.');
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      _throwIfCancelled(cancel);
      try {
        final st = await e.stat();
        final entry = SyncSourceEntry(relative: p.relative(e.path, from: root).replaceAll('\\', '/'),
          size: e is File ? st.size : 0, modified: st.modified, isDir: e is Directory, location: e.path);
        out.add(entry);
        onEntry?.call(entry);
      } catch (_) {}
    }
    return out;
  }
  @override
  Future<Stream<List<int>>> openRead(SyncSourceEntry entry) async => File(entry.location).openRead();
  @override
  Future<void> delete(SyncSourceEntry entry) async => FileSystemEntity.typeSync(entry.location) == FileSystemEntityType.directory
      ? Directory(entry.location).delete(recursive: true)
      : File(entry.location).delete();
}
class _SafSource implements SyncSource {
  _SafSource(this.root);
  final String root;
  final Saf _saf = Saf();

  @override
  Future<List<SyncSourceEntry>> scan({
    CancelToken? cancel,
    void Function(SyncSourceEntry)? onEntry,
    void Function(String relative)? onDirectory,
  }) async {
    final out = <SyncSourceEntry>[];
    final queue = Queue<({String uri, String relative})>()
      ..add((uri: root, relative: ''));
    var active = 0;
    var changed = Completer<void>();
    Object? failure;

    void signalWorkers() {
      final previous = changed;
      changed = Completer<void>();
      if (!previous.isCompleted) previous.complete();
    }

    Future<List<SafDocumentFile>> listCancellable(String uri) {
      _throwIfCancelled(cancel);
      final listing = _saf.list(uri);
      if (cancel == null) return listing;
      return Future.any<List<SafDocumentFile>>([
        listing,
        cancel.whenCancel.then<List<SafDocumentFile>>(
          (_) => throw _cancelledException(),
        ),
      ]);
    }

    Future<void> worker() async {
      while (true) {
        _throwIfCancelled(cancel);
        if (failure != null) throw failure!;
        if (queue.isEmpty) {
          if (active == 0) return;
          final wake = changed.future;
          await wake;
          continue;
        }

        final dir = queue.removeFirst();
        active++;
        signalWorkers();
        try {
          // Report the directory before its provider query so the UI stays live
          // even when a SAF provider takes a long time to enumerate a folder.
          onDirectory?.call(dir.relative);
          final children = await listCancellable(dir.uri);
          _throwIfCancelled(cancel);
          for (final file in children) {
            _throwIfCancelled(cancel);
            final relative = dir.relative.isEmpty
                ? file.name
                : '${dir.relative}/${file.name}';
            final entry = SyncSourceEntry(
              relative: relative.replaceAll('\\\\', '/'),
              size: file.length,
              modified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
              isDir: file.isDir,
              location: file.uri,
            );
            out.add(entry);
            onEntry?.call(entry);
            if (file.isDir) {
              queue.add((uri: file.uri, relative: relative));
            }
          }
        } catch (error) {
          failure ??= error;
        } finally {
          active--;
          signalWorkers();
        }
        if (failure != null) throw failure!;
      }
    }

    // SAF queries are relatively expensive. A small fixed pool overlaps folder
    // listings without flooding document providers with unbounded requests.
    await Future.wait(List.generate(4, (_) => worker()));
    _throwIfCancelled(cancel);
    return out;
  }

  @override
  Future<Stream<List<int>>> openRead(SyncSourceEntry entry) => _saf.readFileStream(entry.location);
  @override
  Future<void> delete(SyncSourceEntry entry) => _saf.delete(entry.location);
}

Future<SyncSourceInfo?> pickSyncSource() async {
  if (Platform.isAndroid) {
    final dir = await Saf().pickDirectory();
    if (dir == null) return null;
    return SyncSourceInfo(kind: 'saf', location: dir.uri, label: dir.name);
  }
  final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose Source Folder');
  if (path == null) return null;
  return SyncSourceInfo(kind: 'path', location: path, label: p.basename(path));
}
SyncSource openSyncSource(SyncSourceInfo info) => info.kind == 'saf' ? _SafSource(info.location) : _PathSource(info.location);

void _throwIfCancelled(CancelToken? cancel) {
  if (cancel?.isCancelled == true) throw _cancelledException();
}

DioException _cancelledException() => DioException(
  requestOptions: RequestOptions(path: ''),
  type: DioExceptionType.cancel,
);
