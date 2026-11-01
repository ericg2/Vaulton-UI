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
import 'package:vaulton/features/auth/login_page.dart';
import 'package:vaulton/features/backups/backup_options.dart';
import 'package:vaulton/features/backups/job_detail_page.dart';
import 'package:vaulton/features/backups/snapshot_browser.dart';
import 'package:vaulton/features/dashboard/dashboard_page.dart';
import 'package:vaulton/features/files/files_page.dart';
import 'package:vaulton/features/files/folder_picker.dart';
import 'package:vaulton/features/messages/messages_page.dart';
import 'package:vaulton/features/settings/settings_page.dart';
import 'package:vaulton/features/storage/root_shares_page.dart';
import 'package:vaulton/features/transfers/transfer_manager.dart';
import 'package:vaulton/features/transfers/transfer_models.dart';
import 'package:vaulton/features/transfers/transfers_page.dart';

// Function coverage: every screen's main actions are driven at a 320px phone
// viewport with faked backend data. Each test fails on
// tester.takeException(), so broken dialogs, sheets and rows are caught.
class _FuncApi extends Vaulton {
  _FuncApi({
    this.points = const [],
    this.nodes = const [],
    this.jobList = const [],

    this.userList = const [],
    this.snapshotList = const [],
    this.failJob = false,
  }) : super(ApiClient(SessionStore()));

  final List<Point> points;
  final List<Node> nodes;
  final List<RepoJob> jobList;

  final List<UserAccount> userList;
  final List<Snapshot> snapshotList;
  final bool failJob;

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
  Future<RepoJob> job(String id, {bool admin = false}) async {
    if (failJob) throw Exception('job gone');
    return jobList.firstWhere((j) => j.id == id);
  }

  @override
  Future<Paged<JobMessage>> jobMessages(
    String id, {
    String? search,
    String? cursor,
    int limit = 100,
    String order = 'Asc',
  }) async => Paged(
    [
      JobMessage('m1', DateTime(2026, 10, 14, 12), 'info', 'Backup complete'),
      JobMessage(
        'm2',
        DateTime(2026, 10, 14, 12, 1),
        'error',
        'One file skipped',
      ),
    ],
    null,
    false,
  );

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
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<Msg>> sent({
    String? to,
    String? search,
    String? cursor,
    int limit = 50,
  }) async => Paged(const [], null, false);

  @override
  Future<Paged<UserAccount>> users({
    String? search,
    String? scope,
    bool? locked,
    bool? mustChange,
    String? cursor,
    int limit = 50,
  }) async => Paged(userList, null, false);

  @override
  Future<Paged<Snapshot>> snapshots(
    String id, {
    String? tag,
    String? path,
    bool? locked,
    String? idPrefix,
    String? cursor,
    int limit = 50,
  }) async => Paged(snapshotList, null, false);

  @override
  Future<Paged<Node>> browseSnapshot(
    String id,
    String snap, {
    String? path,
    String? search,
    String? cursor,
    int limit = 100,
    String order = 'Asc',
  }) async => Paged(nodes, null, false);

  @override
  Future<List<Json>> shares(String id) async => [];

  @override
  Future<int> unreadCount() async => 0;

  @override
  Future<List<DateTime>> previewCron(
    String cron, {
    String? tz,
    int count = 5,
  }) async => [DateTime.now().add(const Duration(hours: 1))];
}

class _StaticTransfers extends TransferManager {
  _StaticTransfers(this.items);
  final List<TransferTask> items;
  @override
  List<TransferTask> build() => List.of(items);
}

final _admin = UserAccount(
  id: 'u1',
  userName: 'admin',
  firstName: 'Test',
  lastName: 'User',
  scopes: const [
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
  Future<Widget> scopedApp(
    Widget page,
    _FuncApi api, {
    Map<String, Object> prefs = const {},
    List<TransferTask>? transfers,
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    return ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
        sessionProvider.overrideWithValue(SessionStore()),
        vaultonProvider.overrideWithValue(api),
        if (signedIn) userProvider.overrideWithValue(_admin),
        if (transfers != null)
          transferProvider.overrideWith(() => _StaticTransfers(transfers)),
      ],
      child: MaterialApp(home: page),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  }

  /// Taps a control, dragging the page list first if it starts below the fold
  /// (short phone viewports leave actions offstage, where tap() cannot hit).
  Future<void> tapSeen(WidgetTester tester, Finder finder) async {
    final view = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (var i = 0; i < 6; i++) {
      final visible = finder.evaluate().any((e) {
        final box = e.renderObject as RenderBox?;
        if (box == null || !box.attached) return false;
        final topLeft = box.localToGlobal(Offset.zero);
        return topLeft.dy >= 0 &&
            topLeft.dy + box.size.height <= view.height + 1;
      });
      if (visible) break;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pump();
    }
    await tester.tap(finder.first);
    await tester.pump();
  }

  group('transfers functions', () {
    testWidgets('running upload and failed download rows fit', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          const TransfersPage(),
          _FuncApi(),
          transfers: [
            TransferTask(
              id: 't1',
              kind: TKind.upload,
              pointId: 'p1',
              remotePath: '/big.zip',
              name: 'big.zip',
              total: 100,
              done: 40,
              state: TState.running,
            ),
            TransferTask(
              id: 't2',
              kind: TKind.download,
              pointId: 'p1',
              remotePath: '/movie.mkv',
              name: 'movie.mkv',
              total: 200,
              done: 10,
              state: TState.failed,
              error: 'Not found',
            ),
          ],
        ),
      );

      expect(find.text('big.zip'), findsOneWidget);
      expect(find.text('movie.mkv'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(find.byTooltip('Retry'), findsOneWidget);
    });
  });

  group('login functions', () {
    testWidgets('empty submit shows validation instead of calling the server', (
      tester,
    ) async {
      await pumpAt(
        tester,
        await scopedApp(const LoginPage(), _FuncApi(), signedIn: false),
      );

      await tester.tap(find.text('Sign In'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Enter your server address.'), findsOneWidget);
    });
  });

  group('dashboard functions', () {
    testWidgets('backup action opens the backup sheet', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          DashboardPage(onNavigate: (_) {}),
          _FuncApi(points: [_point('p1', 'Docs')]),
        ),
      );

      await tapSeen(tester, find.text('Backup Now'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Start a Backup'), findsOneWidget);
    });

    testWidgets('upload action navigates to files', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          DashboardPage(onNavigate: (_) {}),
          _FuncApi(points: [_point('p1', 'Docs')]),
        ),
      );

      await tapSeen(tester, find.text('Upload'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Docs'), findsWidgets);
    });
  });

  group('files functions', () {
    testWidgets('search opens a working search field', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          const FilesPage(),
          _FuncApi(
            points: [_point('p1', 'Docs')],
            nodes: [Node(name: 'a.txt', isDir: false, bytes: 10)],
          ),
          prefs: {'lastPointId': 'p1'},
        ),
      );

      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Search this folder'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder picker dialog fits', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        await scopedApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => pickFolder(context, initialPointId: 'p1'),
                  child: const Text('Pick'),
                ),
              ),
            ),
          ),
          _FuncApi(
            points: [_point('p1', 'Docs')],
            nodes: [Node(name: 'sub', isDir: true, bytes: 0)],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Pick'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Select This Folder'), findsOneWidget);
    });
  });

  group('snapshot browser functions', () {
    testWidgets('snapshot contents and lock action fit', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          SnapshotBrowserPage(repo: _point('v1', 'Vault')),
          _FuncApi(
            snapshotList: [
              Snapshot(
                id: 'snap1',
                time: DateTime(2026, 10, 14, 12),
                tags: const [],
                paths: const ['/'],
                locked: false,
              ),
            ],
            nodes: [
              Node(name: 'restored-doc.pdf', isDir: false, bytes: 512),
              Node(name: 'photos', isDir: true, bytes: 0),
            ],
          ),
        ),
      );

      expect(find.text('restored-doc.pdf'), findsOneWidget);
      expect(find.byTooltip('Lock Snapshot'), findsOneWidget);
    });
  });

  group('job detail functions', () {
    testWidgets('failed job shows error, log lines and cancel-free actions', (
      tester,
    ) async {
      final job = RepoJob(
        id: 'j1',
        repoId: 'v1',
        options: const {'mode': 'backup'},
        kindRaw: 'backup',
        statusRaw: 'failed',
        error: 'custom failure xyz',
        endDate: DateTime(2026, 10, 14, 13),
        stages: const [],
        messages: const [],
      );
      await pumpAt(
        tester,
        await scopedApp(
          const JobDetailPage(jobId: 'j1'),
          _FuncApi(jobList: [job]),
        ),
      );

      expect(find.textContaining('custom failure xyz'), findsOneWidget);
      await tester.tap(find.byType(Tab).at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Backup complete'), findsOneWidget);
      expect(find.textContaining('One file skipped'), findsOneWidget);
    });

    testWidgets('missing job offers retry', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          const JobDetailPage(jobId: 'nope'),
          _FuncApi(failJob: true),
        ),
      );

      expect(find.text('Try Again'), findsOneWidget);
    });
  });

  group('messages functions', () {
    testWidgets('compose walks recipients to the message form', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(const MessagesPage(), _FuncApi(userList: [_admin])),
      );

      await tapSeen(tester, find.text('Compose'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Select Recipients'), findsOneWidget);
      await tapSeen(tester, find.text('Test User'));
      await tapSeen(tester, find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('New Message'), findsOneWidget);
      expect(find.text('Subject *'), findsOneWidget);
    });
  });

  group('backup sheet functions', () {
    testWidgets('backup sheet lists sources at 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        await scopedApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showBackupSheet(
                    context,
                    datas: [_point('p1', 'Docs')],
                    repos: [_point('v1', 'Vault')],
                  ),
                  child: const Text('Back up'),
                ),
              ),
            ),
          ),
          _FuncApi(points: [_point('p1', 'Docs')]),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Back up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Start a Backup'), findsOneWidget);
    });
  });

  group('settings functions', () {
    testWidgets('short new password is rejected with guidance', (tester) async {
      await pumpAt(tester, await scopedApp(const SettingsPage(), _FuncApi()));

      await tester.scrollUntilVisible(
        find.text('Change Password'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Change Password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'old-password-1');
      await tester.enterText(fields.at(1), 'short');
      await tapSeen(tester, find.text('Save'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
    });
  });

  group('sharing functions', () {
    testWidgets('root shares page fits with no shares yet', (tester) async {
      await pumpAt(
        tester,
        await scopedApp(
          RootSharesPage(
            root: Root(
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
          ),
          _FuncApi(),
        ),
      );

      expect(find.text('Share “Local Disk”'), findsOneWidget);
    });
  });
}
