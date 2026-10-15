import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/models.dart';
import 'package:vaulton/core/providers.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/vaulton.dart';
import 'package:vaulton/features/sync/sync_models.dart';
import 'package:vaulton/features/sync/sync_page.dart';

class _SyncPageApi extends Vaulton {
  _SyncPageApi() : super(ApiClient(SessionStore()));

  @override
  Future<Paged<Point>> datas({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async => Paged([_point], null, false);

  @override
  Future<List<DateTime>> previewCron(
    String cron, {
    String? tz,
    int count = 5,
  }) async => [DateTime.now().add(const Duration(hours: 1))];
}

final _point = Point(
  id: 'point-1',
  rootId: 'root-1',
  name: 'Test Data',
  maxBytes: 1024 * 1024,
  usedBytes: 0,
  isReady: true,
  isError: false,
);

void main() {
  const viewports = [
    (width: 320.0, height: 568.0),
    (width: 390.0, height: 844.0),
    (width: 768.0, height: 900.0),
    (width: 1280.0, height: 900.0),
  ];
  for (final viewport in viewports) {
    testWidgets(
      'sync profile fits ${viewport.width.toInt()}×${viewport.height.toInt()} px',
      (tester) async {
        tester.view.physicalSize = Size(viewport.width, viewport.height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('flutter_timezone'),
              (_) async => 'UTC',
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('flutter_timezone'),
                null,
              ),
        );

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final profile = SyncProfile(
          id: 'sync-1',
          name: 'Long Documents Sync Profile',
          sourceKind: 'path',
          sourceLocation: 'C:/Users/Test User/Documents/Work Files',
          sourceLabel: 'Work Documents',
          pointId: _point.id,
          remoteDir: '/Work Documents',
          timeZone: 'UTC',
          nextRun: DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        );
        await SyncProfile.saveAll(prefs, [profile]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              prefsProvider.overrideWithValue(prefs),
              vaultonProvider.overrideWithValue(_SyncPageApi()),
            ],
            child: const MaterialApp(home: SyncPage()),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(find.text(profile.name), findsOneWidget);
        expect(find.text('Sync Now'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.drag(find.byType(ListView).first, const Offset(0, -350));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Sync Settings'), findsOneWidget);
        expect(find.text('Source'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'running sync displays byte progress and a cancel action on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter_timezone'),
            (_) async => 'UTC',
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('flutter_timezone'),
              null,
            ),
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final profile = SyncProfile(
        id: 'sync-running',
        name: 'Running Sync',
        sourceKind: 'path',
        sourceLocation: 'C:/Users/Test User/Documents',
        sourceLabel: 'Documents',
        pointId: _point.id,
        remoteDir: '/Documents',
        timeZone: 'UTC',
        nextRun: DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      );
      await SyncProfile.saveAll(prefs, [profile]);
      await SyncRunStatus(
        running: true,
        phase: 'Uploading New Files',
        bytesDone: 50,
        bytesTotal: 100,
        current: 'large-file.zip',
      ).save(prefs, profile.id);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            vaultonProvider.overrideWithValue(_SyncPageApi()),
          ],
          child: const MaterialApp(home: SyncPage()),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Uploading New Files'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // While a sync runs, starting another one must be impossible.
      final syncNow = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sync Now'),
      );
      expect(syncNow.onPressed, isNull);
      final indicators = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicators.single.value, 0.5);
      expect(tester.takeException(), isNull);
    },
  );
}
