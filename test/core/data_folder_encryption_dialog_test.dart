import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/data_folder_encryption.dart';
import 'package:vaulton/core/models.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/vaulton.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int statusCode = 200;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'point-id',
        'rootId': 'root-id',
        'name': 'Private files',
        'maxBytes': 4096,
        'usedBytes': 0,
        'isReady': true,
        'isError': false,
        'isEncrypted': true,
        'isUnlocked': true,
      }),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Point _point() => Point(
  id: 'point-id',
  rootId: 'root-id',
  name: 'Private files',
  maxBytes: 4096,
  usedBytes: 0,
  isReady: false,
  isError: false,
  isEncrypted: true,
);

void main() {
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

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unlockDataFolderWithPrompt(
                context,
                vaulton: vaulton,
                point: _point(),
              ),
              child: const Text('Open Unlock Dialog'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Unlock Dialog'));
    await tester.pumpAndSettle();
  }

  testWidgets('rejects an invalid password before sending a request', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'short');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 12 characters.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('supports recovery-key unlock and sends only the recovery key', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'temporary password');
    await tester.tap(find.text('Use Recovery Key'));
    await tester.pumpAndSettle();

    expect(find.text('Recovery Key'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a' * 43);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'POST');
    expect(
      adapter.requests.single.uri.path,
      '/datas/point-id/unlock/recovery',
    );
    final body = adapter.requests.single.data;
    final decoded = body is String ? jsonDecode(body) : body;
    expect(decoded, {'recoveryKey': 'a' * 43});
    expect(find.text('Unlock Data Folder'), findsNothing);
  });

  testWidgets('clears credentials after an unsuccessful unlock attempt', (
    tester,
  ) async {
    adapter.statusCode = 400;
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'correct horse battery staple');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Data Folder'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    expect(find.text('Unlocking…'), findsNothing);
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('cancel closes the dialog without sending credentials', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'correct horse battery staple');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Data Folder'), findsNothing);
    expect(adapter.requests, isEmpty);
  });
}
