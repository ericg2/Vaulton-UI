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
import 'package:vaulton/features/admin/admin_page.dart';
import 'package:vaulton/features/auth/login_page.dart';
import 'package:vaulton/features/backups/jobs_page.dart';
import 'package:vaulton/features/dashboard/dashboard_page.dart';
import 'package:vaulton/features/files/files_page.dart';
import 'package:vaulton/features/messages/messages_page.dart';
import 'package:vaulton/features/storage/storage_page.dart';

// Whole-UI runoff suite: every top-level screen is pumped with faked backend
// data at a narrow 320px phone viewport and must lay out without a RenderFlex
// overflow. Each test fails on tester.takeException(), so clipped rows,
// over-wide dialogs and squeezed action bars are caught here instead of on a
// real phone.
class _FakeVaulton extends Vaulton {
  _FakeVaulton({
    this.points = const [],
    this.nodes = const [],
    this.jobList = const [],
    this.scheduleList = const [],
    this.rootList = const [],
    this.msgs = const [],
    this.failSettings = false,
  }) : super(ApiClient(SessionStore()));

  final List<Point> points;
  final List<Node> nodes;
  final List<RepoJob> jobList;
  final List<Schedule> scheduleList;
  final List<Root> rootList;
  final List<Msg> msgs;
  final bool failSettings;

  @override
  Future<Paged<Point>> datas({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async => Paged(points, null, false);

  @override
  Future<Paged<Point>> repos({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async => Paged(points, null, false);

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
  }) async => Paged(jobList, null, false);

  @override
  Future<Paged<Schedule>> schedules({
    String? repoId,
    bool? enabled,
    String? search,
    String? cursor,
    int limit = 50,
  }) async => Paged(scheduleList, null, false);

  @override
  Future<Paged<Root>> roots({
    String? search,
    String? cursor,
    int limit = 50,
  }) async => Paged(rootList, null, false);

  @override
  Future<Paged<Node>> list(
    String pointId,
    String path, {
    String? search,
    String type = 'All',
    String? cursor,
    int limit = 100,
    String order = 'Asc',
  }) async => Paged(nodes, null, false);

  @override
  Future<Paged<Msg>> inbox({
    bool? unread,
    String? from,
    String? search,
    String? cursor,
    int limit = 50,
  }) async => Paged(msgs, null, false);

  @override
  Future<Paged<Msg>> sent({
    String? to,
    String? search,
    String? cursor,
    int limit = 50,
  }) async => Paged(msgs, null, false);

  @override
  Future<Paged<UserAccount>> users({
    String? search,
    String? scope,
    bool? locked,
    bool? mustChange,
    String? cursor,
    int limit = 50,
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<Json>> vfs({
    String? user,
    String? search,
    String? cursor,
    int limit = 100,
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<Json>> logs({
    String? search,
    String? minPriority,
    DateTime? from,
    DateTime? to,
    String? cursor,
    int limit = 100,
    String order = 'Desc',
  }) async => Paged(const [], null, false);

  @override
  Future<Json> status() async => {
    'version': 'test',
    'environment': 'test',
    'backendReachable': true,
    'uptimeSeconds': 61,
  };

  @override
  Future<Json> wolSettings() async {
    if (failSettings) throw Exception('settings unreachable');
    return {};
  }

  @override
  Future<Json> powerSettings() async {
    if (failSettings) throw Exception('settings unreachable');
    return {};
  }

  @override
  Future<Json> powerAgentStatus() async => {};

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<List<DateTime>> previewCron(
    String cron, {
    String? tz,
    int count = 5,
  }) async => [DateTime.now().add(const Duration(hours: 1))];
}

final _admin = UserAccount(
  id: 'u1',
  userName: 'admin',
  scopes: [
    Scopes.usersManage,
    Scopes.rootsManage,
    Scopes.jobsManage,
    Scopes.adminVfs,
    Scopes.adminLogs,
    Scopes.messagesBroadcast,
    Scopes.serverPower,
  ],
  mustChangePassword: false,
  isLockedOut: false,
  emailNotifications: false,
);

Point _point(String id, String name) => Point(
  id: id,
  rootId: 'r1',
  name: name,
  maxBytes: 10 * 1024 * 1024 * 1024,
  usedBytes: 1024 * 1024 * 1024,
  isReady: true,
  isError: false,
);

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget page,
    _FakeVaulton api, {
    double width = 320,
    double height = 568,
    Map<String, Object> prefs = const {},
    bool signedIn = true,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          sessionProvider.overrideWithValue(SessionStore()),
          vaultonProvider.overrideWithValue(api),
          if (signedIn) userProvider.overrideWithValue(_admin),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    // Tab content can repeat the title, so only drive the Tab itself.
    Finder tab() => find.widgetWithText(Tab, label).first;
    // Scrollable tab bars start later tabs off-screen: drag until visible.
    final width = tester.view.physicalSize.width;
    for (var i = 0; i < 5; i++) {
      final dx = tester.getCenter(tab()).dx;
      if (dx > 0 && dx < width) break;
      await tester.drag(find.byType(TabBar).first, const Offset(-200, 0));
      await tester.pump();
    }
    await tester.tap(tab());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  }

  group('top-level screens fit a 320px phone', () {
    testWidgets('login fits', (tester) async {
      await pumpScreen(
        tester,
        const LoginPage(),
        _FakeVaulton(),
        signedIn: false,
      );

      expect(find.text('Sign In to Your Server'), findsOneWidget);
    });

    testWidgets('dashboard empty fits', (tester) async {
      await pumpScreen(
        tester,
        DashboardPage(onNavigate: (_) {}),
        _FakeVaulton(),
      );

      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('dashboard populated fits', (tester) async {
      await pumpScreen(
        tester,
        DashboardPage(onNavigate: (_) {}),
        _FakeVaulton(points: [_point('p1', 'Docs'), _point('p2', 'Media')]),
      );

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Data Folders'), findsOneWidget);
    });

    testWidgets('files empty fits', (tester) async {
      await pumpScreen(tester, const FilesPage(), _FakeVaulton());

      expect(find.textContaining('No data folders yet.'), findsOneWidget);
    });

    testWidgets('files populated fits', (tester) async {
      final api = _FakeVaulton(
        points: [_point('p1', 'Docs')],
        nodes: [
          Node(name: 'report.pdf', isDir: false, bytes: 2048),
          Node(name: 'photos', isDir: true, bytes: 0),
          Node(
            name: 'a-very-long-file-name-that-must-ellipsize-gracefully.zip',
            isDir: false,
            bytes: 1024,
          ),
        ],
      );
      await pumpScreen(
        tester,
        const FilesPage(),
        api,
        prefs: {'lastPointId': 'p1'},
      );

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('photos'), findsOneWidget);
      // Unmounting must dispose the transfer queue cleanly (regression: the
      // manager used to read a provider inside onDispose).
      await tester.pumpWidget(Container());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('storage tabs fit', (tester) async {
      await pumpScreen(
        tester,
        const StoragePage(),
        _FakeVaulton(
          points: [_point('p1', 'Docs')],
          rootList: [
            Root(
              id: 'r1',
              name: 'Local Disk',
              userName: 'admin',
              maxBytes: 100,
              allocatedBytes: 10,
              freeBytes: 90,
              isDataAllowed: true,
              isRepoAllowed: true,
              isOwner: true,
            ),
            Root(
              id: 'r2',
              name: 'Shared Team Drive With A Long Name',
              userName: 'teammate',
              maxBytes: 200,
              allocatedBytes: 150,
              freeBytes: 50,
              isDataAllowed: true,
              isRepoAllowed: false,
              isOwner: false,
            ),
          ],
        ),
      );

      expect(find.text('Data Folders'), findsOneWidget);
      await tapTab(tester, 'Backup Vaults');
      await tapTab(tester, 'Locations');
      // Shared locations report consumed space (max minus free), not free.
      expect(find.textContaining('Available to you:'), findsOneWidget);
    });

    testWidgets('activity tabs fit', (tester) async {
      await pumpScreen(
        tester,
        const BackupsPage(),
        _FakeVaulton(
          jobList: [
            RepoJob(
              id: 'j1',
              repoId: 'p1',
              options: {'mode': 'backup'},
              kindRaw: 'backup',
              statusRaw: 'succeeded',
              endDate: DateTime(2026, 10, 14),
              stages: const [],
              messages: const [],
            ),
          ],
          scheduleList: [
            Schedule(
              id: 's1',
              name: 'Nightly backup of everything',
              repoId: 'p1',
              options: const {'mode': 'backup'},
              cron: '0 2 * * *',
              timeZone: 'UTC',
              enabled: true,
              skipIfRunning: true,
              runCount: 7,
            ),
          ],
        ),
      );

      expect(find.text('Jobs'), findsOneWidget);
      await tapTab(tester, 'Schedules');
      expect(find.text('Nightly backup of everything'), findsOneWidget);
    });

    testWidgets('messages tabs fit', (tester) async {
      await pumpScreen(
        tester,
        const MessagesPage(),
        _FakeVaulton(
          msgs: [
            Msg(
              id: 'm1',
              sender: 'system',
              recipient: 'admin',
              subject: 'A fairly long message subject that must ellipsize',
              preview: 'preview',
              isSystem: true,
              createdAt: DateTime(2026, 10, 14, 12),
              isRead: false,
            ),
          ],
        ),
      );

      expect(find.text('Inbox'), findsOneWidget);
      await tapTab(tester, 'Sent');
      expect(
        find.textContaining('A fairly long message subject'),
        findsWidgets,
      );
    });

    testWidgets('admin tabs fit', (tester) async {
      await pumpScreen(tester, const AdminPage(), _FakeVaulton());

      expect(find.text('Administration'), findsOneWidget);
      for (final tab in ['Users', 'All Jobs', 'VFS', 'Logs', 'Configuration']) {
        await tapTab(tester, tab);
      }
    });

    testWidgets(
      'configuration shows retry instead of a stuck spinner on failure',
      (tester) async {
        await pumpScreen(
          tester,
          const AdminPage(),
          _FakeVaulton(failSettings: true),
        );

        await tapTab(tester, 'Configuration');
        expect(find.text('Try Again'), findsOneWidget);
        await tester.tap(find.text('Try Again'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Try Again'), findsOneWidget);
      },
    );
  });
}
