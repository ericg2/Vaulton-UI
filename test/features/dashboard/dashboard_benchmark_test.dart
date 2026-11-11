import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/models.dart';
import 'package:vaulton/core/providers.dart';
import 'package:vaulton/core/scopes.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/vaulton.dart';
import 'package:vaulton/features/dashboard/dashboard_page.dart';

/// Fake backend with a realistic amount of data so the dashboard's real
/// layout and rebuild cost can be measured.
class _BenchVaulton extends Vaulton {
  _BenchVaulton({
    this.nPoints = 40,
    this.nRepos = 10,
    this.nRoots = 4,
    this.nJobs = 12,
    this.nHealthChecks = 5,
  }) : super(ApiClient(SessionStore()));

  final int nPoints, nRepos, nRoots, nJobs, nHealthChecks;
  int datasCalls = 0;
  int reposCalls = 0;
  int rootsCalls = 0;
  int jobsCalls = 0;
  int healthCalls = 0;

  @override
  Future<Paged<Point>> datas({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async {
    datasCalls++;
    final items = [
      for (var i = 0; i < nPoints; i++)
        Point(
          id: 'd$i',
          rootId: 'r0',
          name: 'Data Folder $i',
          maxBytes: 10 * 1024 * 1024 * 1024,
          usedBytes: 1024 * 1024 * 1024 * (i + 1),
          isReady: true,
          isError: false,
        ),
    ];
    return Paged(items, null, false);
  }

  @override
  Future<Paged<Point>> repos({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async {
    reposCalls++;
    final items = [
      for (var i = 0; i < nRepos; i++)
        Point(
          id: 'v$i',
          rootId: 'r0',
          name: 'Backup Vault $i',
          maxBytes: 10 * 1024 * 1024 * 1024,
          usedBytes: 1024 * 1024 * 1024 * (i + 1),
          isReady: true,
          isError: false,
        ),
    ];
    return Paged(items, null, false);
  }

  @override
  Future<Paged<Root>> roots({
    String? search,
    String? cursor,
    int limit = 50,
  }) async {
    rootsCalls++;
    final items = [
      for (var i = 0; i < nRoots; i++)
        Root(
          id: 'r$i',
          name: 'Location $i',
          userName: 'tester',
          maxBytes: 100 * 1024 * 1024 * 1024,
          allocatedBytes: 10 * 1024 * 1024 * 1024,
          freeBytes: 90 * 1024 * 1024 * 1024,
          isDataAllowed: true,
          isRepoAllowed: true,
          isOwner: true,
        ),
    ];
    return Paged(items, null, false);
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
  }) async {
    jobsCalls++;
    final items = [
      for (var i = 0; i < nJobs; i++)
        RepoJob(
          id: 'j$i',
          repoId: 'v0',
          dataId: 'd0',
          options: const {'path': '/'},
          kindRaw: 'backup',
          statusRaw: i.isEven ? 'Succeeded' : 'Running',
          createdAt: DateTime(2026, 1, 1),
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 1, 1),
          success: true,
          stages: const [],
          messages: const [],
        ),
    ];
    return Paged(items, null, false);
  }

  @override
  Future<Json> healthStatus() async {
    healthCalls++;
    return {
      'status': 'Healthy',
      'checks': [
        for (var i = 0; i < nHealthChecks; i++)
          {
            'name': 'check-$i',
            'status': 'Healthy',
            'description': 'Check $i is healthy',
          },
      ],
    };
  }
}

UserAccount _user() => UserAccount(
      id: 'u1',
      userName: 'tester',
      firstName: 'Test',
      lastName: 'User',
      scopes: const [
        Scopes.jobsManage,
        Scopes.adminLogs,
        Scopes.adminSettings,
        Scopes.rootsManage,
        Scopes.serverPower,
      ],
      mustChangePassword: false,
      isLockedOut: false,
      emailNotifications: false,
    );

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester,
    _BenchVaulton api, {
    double width = 1280,
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
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
          userProvider.overrideWithValue(_user()),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
  }

  testWidgets('dashboard first paint cost', (tester) async {
    final api = _BenchVaulton();
    await pumpDashboard(tester, api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final sw = Stopwatch()..start();
    await tester.pump(const Duration(milliseconds: 16));
    sw.stop();
    debugPrint(
      'DASHBOARD first-frame: ${sw.elapsedMilliseconds}ms, '
      'datas=${api.datasCalls} repos=${api.reposCalls} roots=${api.rootsCalls} '
      'jobs=${api.jobsCalls} health=${api.healthCalls}',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard rebuild cost on epoch bump', (tester) async {
    final api = _BenchVaulton();
    await pumpDashboard(tester, api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DashboardPage)),
    );
    final sw = Stopwatch()..start();
    container.read(epochProvider.notifier).bump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    sw.stop();
    debugPrint(
      'DASHBOARD epoch-rebuild: ${sw.elapsedMilliseconds}ms, '
      'datas=${api.datasCalls} repos=${api.reposCalls} roots=${api.rootsCalls} '
      'jobs=${api.jobsCalls} health=${api.healthCalls}',
    );
  });

  testWidgets('dashboard scroll frame cost', (tester) async {
    final api = _BenchVaulton();
    await pumpDashboard(tester, api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -120));
      await tester.pump();
    }
    sw.stop();
    debugPrint('DASHBOARD 20 scroll frames: ${sw.elapsedMilliseconds}ms');
  });

  testWidgets('control: plain list scroll cost', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: 50,
            itemBuilder: (_, i) => const SizedBox(height: 60, child: Text('row')),
          ),
        ),
      ),
    );
    await tester.pump();

    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pump();
    }
    sw.stop();
    debugPrint('CONTROL 20 scroll frames: ${sw.elapsedMilliseconds}ms');
  });

  testWidgets('dashboard widget tree size', (tester) async {
    final api = _BenchVaulton();
    await pumpDashboard(tester, api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    debugPrint(
      'DASHBOARD widget count: ${tester.allWidgets.length}, '
      'render objects: ${tester.allElements.length}',
    );
  });

  testWidgets('dashboard with a large account', (tester) async {
    final api = _BenchVaulton(
      nPoints: 400,
      nRepos: 120,
      nRoots: 20,
      nJobs: 12,
      nHealthChecks: 8,
    );
    await pumpDashboard(tester, api);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -120));
      await tester.pump();
    }
    sw.stop();
    debugPrint(
      'DASHBOARD large: 20 scroll frames ${sw.elapsedMilliseconds}ms, '
      'widgets=${tester.allWidgets.length}, '
      'datas=${api.datasCalls} repos=${api.reposCalls} roots=${api.rootsCalls} '
      'jobs=${api.jobsCalls} health=${api.healthCalls}',
    );
  });
}
