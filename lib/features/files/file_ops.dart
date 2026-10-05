import '../../core/models.dart';
import '../../core/vaulton.dart';
import '../../core/util.dart';

class RemoteFile {
  RemoteFile(this.path, this.relative, this.size);
  final String path, relative;
  final int size;
}

/// Lists every entry (all pages) in a directory.
Future<List<Node>> listAll(Vaulton v, String pointId, String path) async {
  final out = <Node>[];
  String? cursor;
  do {
    final page = await v.list(pointId, path, cursor: cursor, limit: 200);
    out.addAll(page.items);
    cursor = page.hasMore ? page.nextCursor : null;
  } while (cursor != null);
  return out;
}

/// Recursively collects all files under [path]; [relative] paths start at [base].
Future<List<RemoteFile>> collectFiles(Vaulton v, String pointId, String path, String base,
    {bool Function()? cancelled}) async {
  final out = <RemoteFile>[];
  Future<void> walk(String dir, String rel) async {
    for (final n in await listAll(v, pointId, dir)) {
      if (cancelled?.call() ?? false) return;
      final p = joinPath(dir, n.name);
      final r = rel.isEmpty ? n.name : '$rel/${n.name}';
      if (n.isDir) {
        await walk(p, r);
      } else {
        out.add(RemoteFile(p, r, n.bytes));
      }
    }
  }
  await walk(path, base);
  return out;
}

/// Deletes a file, or a directory and everything in it (the API only deletes empty directories).
Future<int> deleteRecursive(Vaulton v, String pointId, String path, bool isDir,
    {void Function(int deleted)? onProgress, bool Function()? cancelled}) async {
  var count = 0;
  Future<void> rm(String p, bool dir) async {
    if (cancelled?.call() ?? false) throw Exception('Cancelled');
    if (dir) {
      for (final n in await listAll(v, pointId, p)) {
        await rm(joinPath(p, n.name), n.isDir);
      }
    }
    await v.deleteEntry(pointId, p);
    onProgress?.call(++count);
  }
  await rm(path, isDir);
  return count;
}
