import 'dart:io';
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
  Future<List<SyncSourceEntry>> scan();
  Future<Stream<List<int>>> openRead(SyncSourceEntry entry);
  Future<void> delete(SyncSourceEntry entry);
}
class _PathSource implements SyncSource {
  _PathSource(this.root);
  final String root;
  @override
  Future<List<SyncSourceEntry>> scan() async {
    final out = <SyncSourceEntry>[];
    final dir = Directory(root);
    if (!await dir.exists()) throw Exception('Source folder is no longer available.');
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      try {
        final st = await e.stat();
        out.add(SyncSourceEntry(relative: p.relative(e.path, from: root).replaceAll('\\', '/'),
          size: e is File ? st.size : 0, modified: st.modified, isDir: e is Directory, location: e.path));
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
  Future<List<SyncSourceEntry>> scan() async {
    final out = <SyncSourceEntry>[];
    await for (final e in _saf.walk(root)) {
      final f = e.file;
      out.add(SyncSourceEntry(relative: e.relativePath.replaceAll('\\', '/'), size: f.length,
        modified: DateTime.fromMillisecondsSinceEpoch(f.lastModified), isDir: f.isDir, location: f.uri));
    }
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
