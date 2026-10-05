import 'dart:typed_data';

abstract class ByteSink {
  void add(List<int> data);
  Future<void> close();
}

class LocalEntry {
  LocalEntry(this.path, this.relative, this.size, this.modified);
  final String path;
  final String relative; // always '/'-separated
  final int size;
  final DateTime modified;
}

abstract class LocalFilesApi {
  bool get supportsFilesystem;
  Future<int> length(String path); // -1 when missing
  Stream<List<int>> openRead(String path);
  ByteSink openWrite(String path, {bool append = false});
  Future<void> ensureParent(String path);
  Future<void> delete(String path);
  Future<bool> isDirectory(String path);
  Future<List<LocalEntry>> listRecursive(String dir);
  Future<String> downloadsDir();
  Future<void> open(String path);
  Future<void> saveBytes(String name, Uint8List bytes);
}
