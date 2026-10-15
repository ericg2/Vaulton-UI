import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/core/providers.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/widgets.dart';
import 'package:vaulton/features/settings/settings_page.dart';

// Responsive layout suite for the UI cleanup: at a narrow phone (320px), a
// typical phone (390px), tablet (768px) and desktop (1280px) every key screen
// pattern must fit without a RenderFlex overflow. Each test fails on
// tester.takeException() so overflows are caught.
void main() {
  const viewports = [
    (width: 320.0, height: 568.0, label: 'small phone'),
    (width: 390.0, height: 844.0, label: 'phone'),
    (width: 768.0, height: 900.0, label: 'tablet'),
    (width: 1280.0, height: 900.0, label: 'desktop'),
  ];

  void setViewport(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<ProviderScope> appScope(Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        sessionProvider.overrideWithValue(SessionStore()),
      ],
      child: child,
    );
  }

  for (final vp in viewports) {
    testWidgets('navigation bar fits ${vp.label} (${vp.width.toInt()}px)', (
      tester,
    ) async {
      setViewport(tester, vp.width, vp.height);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  label: 'Files',
                ),
                NavigationDestination(
                  icon: Icon(Icons.swap_vert),
                  label: 'Transfers',
                ),
                NavigationDestination(icon: Icon(Icons.apps), label: 'More'),
              ],
            ),
            body: const Center(child: Text('Test')),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('dashboard stats wrap fits ${vp.label} (${vp.width.toInt()}px)', (
      tester,
    ) async {
      setViewport(tester, vp.width, vp.height);

      // Mirrors DashboardPage: LayoutBuilder decides the column count and each
      // stat card gets an exact width inside a Wrap, so narrow screens wrap to
      // two columns instead of overflowing.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (ctx, c) {
                  const count = 4;
                  final cols = c.maxWidth > 700 ? count : 2;
                  final w = (c.maxWidth - 10 * (cols - 1)) / cols;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < count; i++)
                        SizedBox(
                          width: w,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${i + 1}',
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        Text(
                                          'Data Folders with a long label',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Card), findsNWidgets(4));
    });

    testWidgets(
      'files selecting app bar fits ${vp.label} (${vp.width.toInt()}px)',
      (tester) async {
        setViewport(tester, vp.width, vp.height);

        // Mirrors FilesPage selecting state: Close + count + Download + Delete
        // + overflow menu. Move/Copy/Select All live in the menu so the bar
        // never clips at 320px.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                leading: const Icon(Icons.close),
                title: const Text('3 Selected'),
                actions: [
                  IconButton(
                    tooltip: 'Download',
                    icon: const Icon(Icons.download),
                    onPressed: () {},
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {},
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More Actions',
                    onSelected: (_) {},
                    itemBuilder: (c) => const [
                      PopupMenuItem(value: 'select', child: Text('Select All')),
                      PopupMenuItem(value: 'move', child: Text('Move To…')),
                      PopupMenuItem(value: 'copy', child: Text('Copy To…')),
                    ],
                  ),
                ],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('3 Selected'), findsOneWidget);
      },
    );

    testWidgets(
      'snapshot browser app bar fits ${vp.label} (${vp.width.toInt()}px)',
      (tester) async {
        setViewport(tester, vp.width, vp.height);

        // Mirrors SnapshotBrowserPage: Lock + Search + overflow menu (Sort /
        // Restore This Folder / Refresh) instead of five bare icons.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: const Text('snapshot-2026-10-14-120000'),
                actions: [
                  IconButton(
                    tooltip: 'Lock Snapshot',
                    icon: const Icon(Icons.lock_outline),
                    onPressed: () {},
                  ),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () {},
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More Actions',
                    onSelected: (_) {},
                    itemBuilder: (c) => const [
                      PopupMenuItem(
                        value: 'sort',
                        child: Text('Sort Descending'),
                      ),
                      PopupMenuItem(
                        value: 'restore',
                        child: Text('Restore This Folder…'),
                      ),
                      PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                    ],
                  ),
                ],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('storage point card fits ${vp.label} (${vp.width.toInt()}px)', (
      tester,
    ) async {
      setViewport(tester, vp.width, vp.height);

      // Mirrors StoragePage._pointCard: Browse/Backup stack vertically below
      // 320px instead of squeezing side by side.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.folder_outlined),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'A very long data folder name that must ellipsize',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'a-very-long-location-name-that-must-ellipsize',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (_) {},
                              itemBuilder: (c) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'del',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LayoutBuilder(
                          builder: (c, constraints) {
                            final narrow = constraints.maxWidth < 320;
                            final buttons = [
                              FilledButton.tonalIcon(
                                onPressed: () {},
                                icon: const Icon(Icons.folder_open_outlined),
                                label: const Text('Open'),
                              ),
                              FilledButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.backup_outlined),
                                label: const Text('Backup'),
                              ),
                            ];
                            if (narrow) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  buttons[0],
                                  const SizedBox(height: 8),
                                  buttons[1],
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: buttons[0]),
                                const SizedBox(width: 8),
                                Expanded(child: buttons[1]),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Backup'), findsOneWidget);
    });

    testWidgets(
      'amount and unit row fits ${vp.label} (${vp.width.toInt()}px)',
      (tester) async {
        setViewport(tester, vp.width, vp.height);

        // Mirrors _EditPointSheet/_NewPointSheet: the quota Amount + Unit
        // dropdown stack vertically below 360px so text scaling cannot break
        // the 320px layout.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (c, constraints) {
                    final narrow = constraints.maxWidth < 360;
                    final amount = const Expanded(
                      child: TextField(
                        decoration: InputDecoration(labelText: 'Amount'),
                        keyboardType: TextInputType.number,
                      ),
                    );
                    final unit = SizedBox(
                      width: 96,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: 'GiB',
                        items: const ['MiB', 'GiB', 'TiB']
                            .map(
                              (u) => DropdownMenuItem(
                                value: u,
                                child: Text(u, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (_) {},
                      ),
                    );
                    if (narrow) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const TextField(
                            decoration: InputDecoration(labelText: 'Amount'),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 8),
                          unit,
                        ],
                      );
                    }
                    return Row(
                      children: [amount, const SizedBox(width: 10), unit],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('GiB'), findsOneWidget);
      },
    );

    testWidgets('file info dialog fits ${vp.label} (${vp.width.toInt()}px)', (
      tester,
    ) async {
      setViewport(tester, vp.width, vp.height);

      // Mirrors FilesPage._info: insetPadding + double.maxFinite width +
      // SingleChildScrollView with SelectableText so long paths scroll instead
      // of overflowing a short viewport.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  child: const Text('Show Info'),
                  onPressed: () => showDialog(
                    context: c,
                    builder: (ctx) => AlertDialog(
                      title: const Text(
                        'a-very-long-file-name-that-keeps-going.zip',
                        overflow: TextOverflow.ellipsis,
                      ),
                      insetPadding: const EdgeInsets.all(16),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                'Path: /Work Documents/Projects/${'nested/' * 20}file.zip',
                              ),
                              const SelectableText('Size: 1.2 GiB'),
                              const SelectableText(
                                'Modified: Oct 14, 2026, 12:00 PM',
                              ),
                            ],
                          ),
                        ),
                      ),
                      actions: const [
                        TextButton(onPressed: null, child: Text('Close')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show Info'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Path:'), findsOneWidget);
    });

    testWidgets(
      'transfers empty view fits ${vp.label} (${vp.width.toInt()}px)',
      (tester) async {
        setViewport(tester, vp.width, vp.height);

        // Mirrors TransfersPage with an empty queue: AppBar with Clear Finished
        // (disabled when nothing is finished) over the shared EmptyView. The
        // real page needs a live TransferManager, so the layout contract is
        // pinned here instead of pumping backend state.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Transfers'),
                actions: [
                  IconButton(
                    tooltip: 'Clear Finished',
                    icon: const Icon(Icons.clear_all),
                    onPressed: null,
                  ),
                ],
              ),
              body: const EmptyView(
                'No transfers yet.',
                icon: Icons.swap_vert,
                hint: 'Uploads and downloads appear here.',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('No transfers yet.'), findsOneWidget);
        expect(find.byTooltip('Clear Finished'), findsOneWidget);
      },
    );

    testWidgets('settings page fits ${vp.label} (${vp.width.toInt()}px)', (
      tester,
    ) async {
      setViewport(tester, vp.width, vp.height);

      await tester.pumpWidget(
        await appScope(const MaterialApp(home: SettingsPage())),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsWidgets);
      // Section headers render uppercased (see Section in core/widgets.dart).
      // Short viewports virtualize the ListView, so scroll each section into
      // view: this also proves every section fits without overflow.
      for (final section in ['APPEARANCE', 'TRANSFERS', 'SECURITY', 'ABOUT']) {
        await tester.scrollUntilVisible(find.text(section), 200);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text(section), findsOneWidget);
      }
    });
  }

  testWidgets('files selecting app bar fits 320px at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: const Icon(Icons.close),
            title: const Text('3 Selected'),
            actions: [
              IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download),
                onPressed: () {},
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {},
              ),
              PopupMenuButton<String>(
                tooltip: 'More Actions',
                onSelected: (_) {},
                itemBuilder: (c) => const [
                  PopupMenuItem(value: 'select', child: Text('Select All')),
                  PopupMenuItem(value: 'move', child: Text('Move To…')),
                  PopupMenuItem(value: 'copy', child: Text('Copy To…')),
                ],
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
