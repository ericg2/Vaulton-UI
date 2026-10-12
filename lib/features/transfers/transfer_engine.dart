import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/api_client.dart';
import '../../core/util.dart';
import '../../platform/local_files.dart';
import 'transfer_models.dart';

class TransferEngine {
  TransferEngine(this.api);
  final ApiClient api;
  final Set<String> _knownDirs = {};

  Future<void> ensureDirs(String pointId, String dir) async {
    if (dir == '/' || dir.isEmpty) return;
    var cur = '';
    for (final seg in dir.split('/').where((s) => s.isNotEmpty)) {
      cur = '$cur/$seg';
      final key = '$pointId|$cur';
      if (_knownDirs.contains(key)) continue;
      try {
        await api.dio.post('/files/$pointId/directories', data: {'path': cur});
      } on DioException catch (_) {}
      _knownDirs.add(key);
    }
  }

  Future<void> upload(TransferTask t, {
    Uint8List? bytes,
    required void Function(int sent, int total) onProgress,
    CancelToken? cancel,
  }) async {
    try {
      await ensureDirs(t.pointId, parentPath(t.remotePath));
      final q = {'path': t.remotePath, 'overwrite': t.overwrite};
      if (bytes != null) {
        await api.dio.put('/files/${t.pointId}/content',
          queryParameters: q,
          data: bytes,
          options: Options(contentType: 'application/octet-stream'),
          onSendProgress: onProgress,
          cancelToken: cancel);
      } else {
        final len = await localFiles.length(t.localPath!);
        if (len < 0) throw ApiException('Local file no longer exists');
        await api.dio.put('/files/${t.pointId}/content',
          queryParameters: q,
          data: localFiles.openRead(t.localPath!),
          options: Options(contentType: 'application/octet-stream', headers: {Headers.contentLengthHeader: len}),
          onSendProgress: onProgress,
          cancelToken: cancel);
      }
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> uploadStream({
    required String pointId,
    required String remotePath,
    required Stream<List<int>> stream,
    required int size,
    bool overwrite = true,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    try {
      await ensureDirs(pointId, parentPath(remotePath));
      await api.dio.put(
        '/files/$pointId/content',
        queryParameters: {'path': remotePath, 'overwrite': overwrite},
        data: stream,
        options: Options(
          contentType: 'application/octet-stream',
          headers: {Headers.contentLengthHeader: size},
        ),
        onSendProgress: onProgress,
        cancelToken: cancel,
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  String _contentUrl(TransferTask t) => t.snapshotId != null
      ? '/repos/${t.pointId}/snapshots/${Uri.encodeComponent(t.snapshotId!)}/content'
      : '/files/${t.pointId}/content';

  Future<void> download(TransferTask t, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancel,
  }) async {
    try {
      if (!localFiles.supportsFilesystem) {
        final r = await api.dio.get<List<int>>(_contentUrl(t),
          queryParameters: {'path': t.remotePath},
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: onProgress,
          cancelToken: cancel);
        await localFiles.saveBytes(t.name, Uint8List.fromList(r.data!));
        return;
      }
      final path = t.localPath!;
      await localFiles.ensureParent(path);
      var have = await localFiles.length(path);
      if (have < 0) have = 0;
      if (t.total > 0 && have > t.total) {
        await localFiles.delete(path);
        have = 0;
      }
      if (t.total > 0 && have == t.total) {
        onProgress(have, t.total);
        return;
      }
      final r = await api.dio.get<ResponseBody>(_contentUrl(t),
        queryParameters: {'path': t.remotePath},
        options: Options(
          responseType: ResponseType.stream,
          headers: have > 0 ? {'Range': 'bytes=$have-'} : null,
          validateStatus: (s) => s == 200 || s == 206 || s == 416,
        ),
        cancelToken: cancel);
      if (r.statusCode == 416) return;
      final append = r.statusCode == 206 && have > 0;
      var received = append ? have : 0;
      final len = int.tryParse(r.headers.value('content-length') ?? '') ?? 0;
      final total = t.total > 0 ? t.total : len + (append ? have : 0);
      final sink = localFiles.openWrite(path, append: append);
      try {
        await for (final chunk in r.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
