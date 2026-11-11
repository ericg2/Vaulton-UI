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
import 'package:vaulton/features/backups/jobs_page.dart';
import 'package:vaulton/features/dashboard/dashboard_page.dart';
import 'package:vaulton/features/files/files_page.dart';
import 'package:vaulton/features/messages/messages_page.dart';
import 'package:vaulton/features/storage/storage_page.dart';

/// Fake backend with a realistic amount of rows so the scroll cost of the
/// real screens can be measured.
class _BenchVaulton extends Vaulton {
  _BenchVaulton({
    this.nPoints = 60,
    this.nNodes = 200,
    this.nJobs = 60,
    this.nMsgs = 60,
    this.nRoots = 6,
  }) : super(ApiClient(SessionStore()));

  final int nPoints, nNodes, nJobs, nMsgs, nRoots;

  @override
  Future<Paged<Point>> datas({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async =>
      Paged([
        for (var i = 0; i < nPoints; i++)
          Point(
            id: 'd$i',
            rootId: 'r0',
            name: 'Data Folder $i',
            maxBytes: 10 * 1024 * 1024 * 1024,
            usedBytes: 1024 * 1024 * 1024 * (i + 1),
            isReady: true,
            isError: i % 17 == 0,
          ),
      ], null, false);

  @override
  Future<Paged<Point>> repos({
    String? rootId,
    String? search,
    String? cursor,
    int limit = 100,
  }) async =>
      Paged([
        for (var i = 0; i < nPoints; i++)
          Point(
            id: 'v$i',
            rootId: 'r0',
            name: 'Backup Vault $i',
            maxBytes: 10 * 1024 * 1024 * 1024,
            usedBytes: 1024 * 1024 * 1024 * (i + 1),
            isReady: true,
            isError: false,
          ),
      ], null, false);

  @override
  Future<Paged<Root>> roots({
    String? search,
    String? cursor,
    int limit = 50,
  }) async =>
      Paged([
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
      ], null, false);

  @override
  Future<Paged<Node>> list(
    String pointId,
    String path, {
    String? search,
    String type = 'All',
    String? cursor,
    int limit = 100,
    String order = 'Asc',
  }) async =>
      Paged([
        for (var i = 0; i < nNodes; i++)
          Node(
            name: 'File $i.txt',
            isDir: i % 5 == 0,
            bytes: 1024 * (i + 1),
            modified: DateTime(2026, 1, 1),
          ),
      ], null, false);

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
  }) async =>
      Paged([
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
      ], null, false);

  @override
  Future<Paged<Msg>> inbox({
    bool? unread,
    String? from,
    String? search,
    String? cursor,
    int limit = 50,
  }) async =>
      Paged([
        for (var i = 0; i < nMsgs; i++)
          Msg(
            id: 'm$i',
            sender: 'someone@example.com',
            recipient: 'tester',
            subject: 'Message $i',
            preview: 'This is the preview of message $i.',
            isSystem: false,
            createdAt: DateTime(2026, 1, 1),
            isRead: i.isEven,
          ),
      ], null, false);

  @override
  Future<Paged<Msg>> sent({
    String? to,
    String? search,
    String? cursor,
    int limit = 50,
  }) async =>
      inbox();

  @override
  Future<Json> status() async => {
        'version': 'test',
        'environment': 'test',
        'backendReachable': true,
        'uptimeSeconds': 61,
      };

  @override
  Future<Json> healthStatus() async => {
        'status': 'Healthy',
        'checks': [
          for (var i = 0; i < 4; i++)
            {'name': 'check-$i', 'status': 'Healthy', 'description': 'Check $i is healthy'},
        ],
      };

  @override
  Future<int> unreadCount() async => 0;
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
        Scopes.messagesBroadcast,
      ],
      mustChangePassword: false,
      isLockedOut: false,
      emailNotifications: false,
    );

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget page, {
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
          prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
          sessionProvider.overrideWithValue(SessionStore()),
          vaultonProvider.overrideWithValue(_BenchVaulton()),
          userProvider.overrideWithValue(_user()),
        ],
        child: MaterialApp(home: page),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
  }

  /// The vertical scroller of the screen under test.
  ScrollableState verticalScroller(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((s) => s.axisDirection == AxisDirection.down);

  /// Drags the list and returns the cost of 20 frames.
  ///
  /// The drag starts from the middle of the viewport so the measurement does
  /// not include the cost of looking the list up in the widget tree. The
  /// fastest of three rounds is reported, which is the most stable number on
  /// a busy machine.
  Future<int> measureScroll(WidgetTester tester) async {
    const start = Offset(640, 450);
    var best = 1 << 30;
    for (var round = 0; round < 5; round++) {
      // Start every round at the top so each one scrolls the same distance.
      verticalScroller(tester).position.jumpTo(0);
      await tester.pump();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        await tester.dragFrom(start, const Offset(0, -140));
        await tester.pump();
      }
      sw.stop();
      if (sw.elapsedMilliseconds < best) best = sw.elapsedMilliseconds;
    }
    return best;
  }

  /// How far the list actually moved, so a benchmark run that did not scroll
  /// cannot look fast.
  double scrollOffset(WidgetTester tester) => verticalScroller(tester).position.pixels;

  Future<void> report(WidgetTester tester, String name, int ms, double moved) async {
    debugPrint(
      'SCROLL $name: $ms ms / 20 frames, moved ${moved.round()}px, '
      'widgets=${tester.allWidgets.length}',
    );
  }

  testWidgets('files list scroll cost', (tester) async {
    await pumpScreen(tester, const FilesPage());
    expect(tester.takeException(), isNull);
    final before = scrollOffset(tester);
    final ms = await measureScroll(tester);
    await report(tester, 'files', ms, scrollOffset(tester) - before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('storage list scroll cost', (tester) async {
    await pumpScreen(tester, const StoragePage(initialTab: 0));
    expect(tester.takeException(), isNull);
    final before = scrollOffset(tester);
    final ms = await measureScroll(tester);
    await report(tester, 'storage', ms, scrollOffset(tester) - before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity list scroll cost', (tester) async {
    await pumpScreen(tester, const BackupsPage());
    expect(tester.takeException(), isNull);
    final before = scrollOffset(tester);
    final ms = await measureScroll(tester);
    await report(tester, 'activity', ms, scrollOffset(tester) - before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('messages list scroll cost', (tester) async {
    await pumpScreen(tester, const MessagesPage());
    expect(tester.takeException(), isNull);
    final before = scrollOffset(tester);
    final ms = await measureScroll(tester);
    await report(tester, 'messages', ms, scrollOffset(tester) - before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard scroll cost', (tester) async {
    await pumpScreen(tester, const DashboardPage());
    expect(tester.takeException(), isNull);
    final before = scrollOffset(tester);
    final ms = await measureScroll(tester);
    await report(tester, 'dashboard', ms, scrollOffset(tester) - before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity scroll while the job poll runs', (tester) async {
    await pumpScreen(tester, const BackupsPage());
    expect(tester.takeException(), isNull);
    // The job list polls every three seconds. Scrolling across that poll is
    // what makes a list feel like it stutters.
    final sw = Stopwatch()..start();
    for (var i = 0; i < 30; i++) {
      await tester.dragFrom(const Offset(640, 450), const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 200));
    }
    sw.stop();
    debugPrint('SCROLL activity + polling: ${sw.elapsedMilliseconds} ms / 30 frames');
    expect(tester.takeException(), isNull);
  });

  testWidgets('files list scroll cost with a large folder', (tester) async {
    final api = _BenchVaulton(nPoints: 400, nNodes: 800, nJobs: 200, nMsgs: 200, nRoots: 20);
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
          sessionProvider.overrideWithValue(SessionStore()),
          vaultonProvider.overrideWithValue(api),
          userProvider.overrideWithValue(_user()),
        ],
        child: const MaterialApp(home: FilesPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    final ms = await measureScroll(tester);
    debugPrint('SCROLL files (large): $ms ms / 20 frames');
    expect(tester.takeException(), isNull);
  });
}
