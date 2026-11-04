import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/vaulton.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = options.uri.path.endsWith('/encryption/status')
        ? <String, dynamic>{'enabled': true}
        : <String, dynamic>{
            'id': 'point-id',
            'rootId': 'root-id',
            'name': 'Private files',
            'maxBytes': 4096,
            'usedBytes': 12,
            'isReady': true,
            'isError': false,
            'isEncrypted': true,
            'isUnlocked': true,
            if (options.uri.path.endsWith('/recovery-key/rotate'))
              'recoveryKey': 'one-time-recovery-secret',
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('Data Folder encryption API client', () {
    late ApiClient api;
    late Vaulton vaulton;
    late _RecordingAdapter adapter;

    setUp(() {
      final session = SessionStore()
        ..baseUrl = 'http://vaulton.test:5141'
        ..accessToken = 'test-access-token';
      api = ApiClient(session);
      adapter = _RecordingAdapter();
      api.dio.httpClientAdapter = adapter;
      vaulton = Vaulton(api);
    });

    tearDown(() => api.dio.close(force: true));

    test('uses the documented lifecycle routes and HTTP methods', () async {
      expect(await vaulton.dataFolderEncryptionEnabled(), isTrue);

      await vaulton.createData({
        'rootId': 'root-id',
        'name': 'Private files',
        'maxBytes': 4096,
        'encryptionPassword': 'correct horse battery staple',
      });
      await vaulton.unlockData('point-id', 'correct horse battery staple');
      await vaulton.recoverData('point-id', 'recovery-secret');
      await vaulton.changeDataPassword(
        'point-id',
        'old password',
        'new password',
      );
      final rotated = await vaulton.rotateDataRecoveryKey(
        'point-id',
        'new password',
      );
      expect(rotated.recoveryKey, 'one-time-recovery-secret');
      await vaulton.lockData('point-id');
      await vaulton.deleteData(
        'point-id',
        confirmEncryptedKeyRemoval: true,
      );

      expect(
        adapter.requests.map((request) => (
          request.method,
          request.uri.path,
        )).toList(),
        [
          ('GET', '/datas/encryption/status'),
          ('POST', '/datas'),
          ('POST', '/datas/point-id/unlock'),
          ('POST', '/datas/point-id/unlock/recovery'),
          ('POST', '/datas/point-id/password/change'),
          ('POST', '/datas/point-id/recovery-key/rotate'),
          ('POST', '/datas/point-id/lock'),
          ('DELETE', '/datas/point-id'),
        ],
      );
      expect(
        adapter.requests.last.uri.queryParameters,
        {'confirmEncryptedKeyRemoval': 'true'},
      );
    });

    test('sends credentials only in the intended lifecycle request bodies', () async {
      await vaulton.unlockData('point-id', 'folder-password');
      await vaulton.recoverData('point-id', 'recovery-secret');
      await vaulton.changeDataPassword(
        'point-id',
        'current-password',
        'replacement-password',
      );

      expect(adapter.requests[0].data, {'password': 'folder-password'});
      expect(adapter.requests[1].data, {'recoveryKey': 'recovery-secret'});
      expect(adapter.requests[2].data, {
        'currentPassword': 'current-password',
        'newPassword': 'replacement-password',
      });
      expect(
        adapter.requests.every(
          (request) => request.uri.queryParameters.isEmpty,
        ),
        isTrue,
      );
    });

    test('URL-encodes point identifiers consistently', () async {
      await vaulton.lockData('point/id with spaces');

      expect(
        adapter.requests.single.uri.path,
        '/datas/point%2Fid%20with%20spaces/lock',
      );
    });
  });
}
