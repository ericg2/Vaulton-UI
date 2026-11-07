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
import 'package:vaulton/features/storage/storage_page.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int statusCode = 200;
  Map<String, Object?> responseBody = {
    'id': 'point-id',
    'rootId': 'root-id',
    'name': 'Private files',
    'maxBytes': 4096,
    'usedBytes': 0,
    'isReady': true,
    'isError': false,
    'isEncrypted': true,
    'isUnlocked': true,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(responseBody),
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

  testWidgets('automatically unlocks with the signed-in account password', (
    tester,
  ) async {
    var unlocked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                unlocked = await unlockDataFolderWithPrompt(
                  context,
                  vaulton: vaulton,
                  point: _point(),
                  accountPassword: 'correct horse battery staple',
                );
              },
              child: const Text('Auto Unlock'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Auto Unlock'));
    await tester.pumpAndSettle();

    expect(unlocked, isTrue);
    expect(find.text('Unlock Data Folder'), findsNothing);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.uri.path, '/datas/point-id/unlock');
    final body = adapter.requests.single.data;
    final decoded = body is String ? jsonDecode(body) : body;
    expect(decoded, {'password': 'correct horse battery staple'});
  });

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

  testWidgets('rejects malformed recovery keys before sending a request', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.tap(find.text('Use Recovery Key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'not-a-recovery-key');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Enter the 43-character recovery key.'), findsOneWidget);
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
    final recoveryKey = List.filled(43, 'a').join();
    await tester.enterText(find.byType(TextField), recoveryKey);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.uri.path, '/datas/point-id/unlock/recovery');
    final body = adapter.requests.single.data;
    final decoded = body is String ? jsonDecode(body) : body;
    expect(decoded, {'recoveryKey': recoveryKey});
    expect(find.text('Unlock Data Folder'), findsNothing);
  });

  testWidgets('clears credentials after an unsuccessful unlock attempt', (
    tester,
  ) async {
    adapter.statusCode = 400;
    await openDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      'correct horse battery staple',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Data Folder'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Unlocking…'), findsNothing);
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('cancel closes the dialog without sending credentials', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      'correct horse battery staple',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock Data Folder'), findsNothing);
    expect(adapter.requests, isEmpty);
  });

  testWidgets(
    'creates an encrypted Data Folder and protects its one-time recovery key',
    (tester) async {
      final recoveryKey = List.filled(43, 'r').join();
      adapter.responseBody = {
        'id': 'created-point',
        'rootId': 'root-id',
        'name': 'Private files',
        'maxBytes': 4096,
        'usedBytes': 0,
        'isReady': true,
        'isError': false,
        'isEncrypted': true,
        'isUnlocked': true,
        'recoveryKey': recoveryKey,
      };
      final root = Root(
        id: 'root-id',
        name: 'Local storage',
        userName: 'admin',
        maxBytes: 16 * 1024 * 1024,
        allocatedBytes: 0,
        freeBytes: 16 * 1024 * 1024,
        isDataAllowed: true,
        isRepoAllowed: true,
        isOwner: true,
      );
      var created = false;

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  final result = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => NewDataPointSheet(
                      roots: [root],
                      vaulton: vaulton,
                      repo: false,
                      encryptionEnabled: true,
                      accountPassword: 'correct horse battery staple',
                    ),
                  );
                  created = result == true;
                },
                child: const Text('Create Folder'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Create Folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encrypt This Data Folder'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B').last);
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Private files');
      await tester.enterText(fields.at(1), '4096');

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Save Your Recovery Key'), findsOneWidget);
      expect(find.textContaining(recoveryKey), findsOneWidget);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.uri.path, '/datas');
      final requestBody = adapter.requests.single.data;
      final decoded = requestBody is String
          ? jsonDecode(requestBody) as Map<String, dynamic>
          : Map<String, dynamic>.from(requestBody as Map);
      expect(decoded['encryptionPassword'], 'correct horse battery staple');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Save Your Recovery Key'), findsOneWidget);

      await tester.tap(find.text('I Have Saved It'));
      await tester.pumpAndSettle();
      expect(find.text('Save Your Recovery Key'), findsNothing);
      expect(created, isTrue);
    },
  );
}
