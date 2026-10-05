import 'dart:io';
import 'dart:typed_data';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'local_files_base.dart';

class _Sink implements ByteSink {
  _Sink(this._s);
  final IOSink _s;
  @override
  void add(List<int> data) => _s.add(data);
  @override
  Future<void> close() async {
    await _s.flush();
    await _s.close();
  }
}

class _IoFiles implements LocalFilesApi {
  @override
  bool get supportsFilesystem => true;

  @override
  Future<int> length(String path) async {
    final f = File(path);
    return await f.exists() ? await f.length() : -1;
  }

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();

  @override
  ByteSink openWrite(String path, {bool append = false}) =>
      _Sink(File(path).openWrite(mode: append ? FileMode.append : FileMode.write));

  @override
  Future<void> ensureParent(String path) => Directory(p.dirname(path)).create(recursive: true);

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<bool> isDirectory(String path) => FileSystemEntity.isDirectory(path);

  @override
  Future<List<LocalEntry>> listRecursive(String dir) async {
    final out = <LocalEntry>[];
    await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          final st = await e.stat();
          out.add(LocalEntry(e.path, p.relative(e.path, from: dir).replaceAll('\\', '/'), st.size, st.modified));
        } catch (_) {}
      }
    }
    return out;
  }

  @override
  Future<String> downloadsDir() async {
    Directory? d;
    if (Platform.isAndroid) {
      d = await getExternalStorageDirectory();
    } else {
      d = await getDownloadsDirectory();
    }
    d ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(d.path, 'Vaulton'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<void> open(String path) async {
    await OpenFilex.open(path);
  }

  @override
  Future<void> saveBytes(String name, Uint8List bytes) async {
    final path = p.join(await downloadsDir(), name);
    await File(path).writeAsBytes(bytes);
  }
}

final LocalFilesApi localFiles = _IoFiles();
