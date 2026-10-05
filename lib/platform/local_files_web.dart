import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'local_files_base.dart';

class _WebFiles implements LocalFilesApi {
  Never _no() => throw UnsupportedError('Not available in the browser');
  @override
  bool get supportsFilesystem => false;
  @override
  Future<int> length(String path) async => -1;
  @override
  Stream<List<int>> openRead(String path) => _no();
  @override
  ByteSink openWrite(String path, {bool append = false}) => _no();
  @override
  Future<void> ensureParent(String path) async {}
  @override
  Future<void> delete(String path) async {}
  @override
  Future<bool> isDirectory(String path) async => false;
  @override
  Future<List<LocalEntry>> listRecursive(String dir) async => [];
  @override
  Future<String> downloadsDir() async => '';
  @override
  Future<bool> open(String path) async => false;
  @override
  Future<bool> openContainingFolder(String path) async => false;

  @override
  Future<void> saveBytes(String name, Uint8List bytes) async {
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = name;
    web.document.body?.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
  }
}

final LocalFilesApi localFiles = _WebFiles();
