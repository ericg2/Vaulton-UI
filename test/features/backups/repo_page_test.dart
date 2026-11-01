import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/models.dart';
import 'package:vaulton/core/providers.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/vaulton.dart';
import 'package:vaulton/features/backups/repo_page.dart';

class _RepoFake extends Vaulton {
  _RepoFake({this.failRepo = false}) : super(ApiClient(SessionStore()));

  final bool failRepo;

  @override
  Future<Point> repo(String id) async {
    if (failRepo) throw Exception('vault unreachable');
    return Point(
      id: id,
      rootId: 'r1',
      name: 'Nightly Vault',
      maxBytes: 10 * 1024 * 1024 * 1024,
      usedBytes: 1024 * 1024 * 1024,
      isReady: true,
      isError: false,
    );
  }

  @override
  Future<Paged<RepoJob>> jobs({
    String? repoId,
    String? dataId,
    String? kind,
    String? status,
    String? cursor,
    int limit = 50,
    String order = 'Desc',
    bool admin = false,
    String? userName,
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<Snapshot>> snapshots(
    String id, {
    String? tag,
    String? path,
    bool? locked,
    String? idPrefix,
    String? cursor,
    int limit = 50,
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<Schedule>> schedules({
    String? repoId,
    bool? enabled,
    String? search,
    String? cursor,
    int limit = 50,
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<Point>> datas({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async => Paged(const [], null, false);
}

void main() {
  Future<void> pumpRepo(
    WidgetTester tester,
    _RepoFake api, {
    Point? repo,
  }) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          sessionProvider.overrideWithValue(SessionStore()),
          vaultonProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          home: RepoPage(repoId: 'v1', repo: repo),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'shows a retry state instead of a stuck loader when the vault fails to load',
    (tester) async {
      await pumpRepo(tester, _RepoFake(failRepo: true));

      // The vault summary lives on the Activity tab.
      await tester.tap(find.text('Activity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Could not load vault details.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Retry surfaces the same error instead of hanging.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Could not load vault details.'), findsOneWidget);
    },
  );

  testWidgets('vault summary and tabs fit a 320px phone', (tester) async {
    await pumpRepo(
      tester,
      _RepoFake(),
      repo: Point(
        id: 'v1',
        rootId: 'r1',
        name: 'Nightly Vault',
        maxBytes: 10 * 1024 * 1024 * 1024,
        usedBytes: 1024 * 1024 * 1024,
        isReady: true,
        isError: false,
      ),
    );

    // The summary lives on the Activity tab, which builds lazily on selection.
    await tester.tap(find.text('Activity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
    await tester.tap(find.text('Automation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
