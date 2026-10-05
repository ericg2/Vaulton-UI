import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import '../admin/admin_page.dart';
import '../backups/jobs_page.dart';
import '../dashboard/dashboard_page.dart';
import 'account_actions.dart';
import 'server_badge.dart';
import '../files/files_page.dart';
import '../messages/messages_page.dart';
import '../settings/settings_page.dart';
import '../storage/storage_page.dart';
import '../sync/folder_sync.dart';
import '../sync/sync_models.dart';
import '../sync/sync_page.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfers_page.dart';

class _Dest {
  _Dest(this.label, this.icon, this.selected, this.build);
  final String label;
  final IconData icon, selected;
  final Widget Function() build;
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  int _storageTab = 0;
  final _visited = <int>{0};
  late final AppLifecycleListener _life;
  Timer? _folderTimer;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onStateChange: (s) => ref.read(transferProvider.notifier).onLifecycle(s));
    // Desktop: closing with active transfers offers to minimise instead of quitting.
    setCloseGuard(() => ref.read(transferProvider.notifier).hasActive, () async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      final r = await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('Transfers in Progress'),
          content: const Text('Uploads/downloads are still running. Minimise Vaulton to keep them going, or quit and resume them next time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Quit')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Minimise')),
          ],
        ),
      );
      return r ?? true;
    });
    // Desktop folder-sync scheduler (runs while the app is open).
    if (isDesktop) {
      _folderTimer = Timer.periodic(const Duration(minutes: 1), (_) => _tickFolders());
      Future.delayed(const Duration(seconds: 5), _tickFolders);
    }
  }

  Future<void> _tickFolders() async {
    final prefs = ref.read(prefsProvider);
    final pairs = FolderPair.loadAll(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final p in pairs.where((p) => p.enabled && now - p.lastRun >= p.intervalMinutes * 60000)) {
      try {
        await runFolderPair(p, prefs, ref.read(transferProvider.notifier));
      } catch (_) {}
      changed = true;
    }
    if (changed) await FolderPair.saveAll(prefs, pairs);
  }

  @override
  void dispose() {
    _life.dispose();
    _folderTimer?.cancel();
    super.dispose();
  }

  void _goto(String label, List<_Dest> dests, bool wide) {
    if (label == 'Data Points' || label == 'Repositories') {
      _storageTab = label == 'Data Points' ? 1 : 2;
      final storage = dests.indexWhere((d) => d.label == 'Storage');
      if (storage >= 0) {
        setState(() {
          _index = storage;
          _visited.add(storage);
        });
      }
      return;
    }
    final i = dests.indexWhere((d) => d.label == label);
    if (i < 0) return;
    if (wide || i < 4) {
      setState(() {
        _index = i;
        _visited.add(i);
      });
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => dests[i].build()));
    }
  }

  List<_Dest> _dests(UserAccount u, bool wide) => [
        _Dest('Dashboard', Icons.dashboard_outlined, Icons.dashboard, () => DashboardPage(onNavigate: (l) => _goto(l, _dests(ref.read(userProvider)!, wide), wide))),
        _Dest('Files', Icons.folder_outlined, Icons.folder, () => const FilesPage()),
        _Dest('Transfers', Icons.swap_vert, Icons.swap_vert, () => const TransfersPage()),
        _Dest('Storage', Icons.storage_outlined, Icons.storage, () => StoragePage(key: ValueKey(_storageTab), initialTab: _storageTab)),
        if (u.has(Scopes.jobsManage)) _Dest('Recent Jobs', Icons.history_outlined, Icons.history, () => const BackupsPage()),
        _Dest('Sync', Icons.cloud_sync_outlined, Icons.cloud_sync, () => const SyncPage()),
        _Dest('Messages', Icons.mail_outline, Icons.mail, () => const MessagesPage()),
        if (u.hasAny(Scopes.admin)) _Dest('Admin', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, () => const AdminPage()),
        _Dest('Settings', Icons.settings_outlined, Icons.settings, () => const SettingsPage()),
      ];

  Widget _icon(_Dest d, bool sel, int unread, int active) {
    final base = Icon(sel ? d.selected : d.icon);
    if (d.label == 'Messages' && unread > 0) return Badge(label: Text('$unread'), child: base);
    if (d.label == 'Transfers' && active > 0) return Badge(label: Text('$active'), child: base);
    return base;
  }

  Widget _withAndroidBack(Widget child) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          setState(() {
            _index = 0;
            _visited.add(0);
          });
        } else {
          SystemNavigator.pop();
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(userProvider);
    if (u == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final dests = _dests(u, wide);
    final unread = ref.watch(unreadProvider).value ?? 0;
    final active = ref.watch(transferProvider.select((l) => l.where((t) => t.active).length));
    final extended = MediaQuery.sizeOf(context).width >= 1150;
    if (_index >= (wide ? dests.length : 5)) _index = 0;

    Widget body(int i) => _visited.contains(i) ? dests[i].build() : const SizedBox.shrink();

    if (wide) {
      return _withAndroidBack(Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: extended,
            selectedIndex: _index,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() {
              _index = i;
              _visited.add(i);
            }),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: extended
                      ? TextButton.icon(onPressed: () => signOutFlow(context, ref), icon: const Icon(Icons.logout), label: const Text('Sign Out'))
                      : IconButton(tooltip: 'Sign Out', onPressed: () => signOutFlow(context, ref), icon: const Icon(Icons.logout)),
                ),
              ),
            ),
            leading: extended
                ? const ServerBadge()
                : const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: ServerBadge(compact: true)),
            destinations: [
              for (var i = 0; i < dests.length; i++)
                NavigationRailDestination(
                  icon: _icon(dests[i], false, unread, active),
                  selectedIcon: _icon(dests[i], true, unread, active),
                  label: Text(dests[i].label),
                ),
            ],
          ),
          Expanded(child: _FadeIndexed(index: _index, children: [for (var i = 0; i < dests.length; i++) body(i)])),
        ]),
      ));
    }

    // Phones: 4 primary tabs + "More" which lists the rest.
    final primary = dests.take(4).toList();
    final rest = dests.skip(4).toList();
    final onMore = _index == 4;
    return _withAndroidBack(Scaffold(
      body: _FadeIndexed(index: _index, children: [
        for (var i = 0; i < 4; i++) body(i),
        _MorePage(items: rest, onSignOut: () => signOutFlow(context, ref)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: [
          for (final d in primary)
            NavigationDestination(icon: _icon(d, false, unread, active), selectedIcon: _icon(d, true, unread, active), label: d.label),
          NavigationDestination(icon: Icon(onMore ? Icons.apps : Icons.apps_outlined), label: 'More'),
        ],
      ),
    ));
  }
}

/// IndexedStack that keeps every visited tab alive (scroll position, loaded data)
/// but fades the newly selected one in, so switching tabs is smooth, not a hard cut.
class _FadeIndexed extends StatefulWidget {
  const _FadeIndexed({required this.index, required this.children});
  final int index;
  final List<Widget> children;
  @override
  State<_FadeIndexed> createState() => _FadeIndexedState();
}

class _FadeIndexedState extends State<_FadeIndexed> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void didUpdateWidget(covariant _FadeIndexed old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _c.forward(from: 0.0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(_fade),
        child: IndexedStack(index: widget.index, children: widget.children),
      );
}

class _MorePage extends StatelessWidget {
  const _MorePage({required this.items, required this.onSignOut});
  final List<_Dest> items;
  final VoidCallback onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('More')),
        body: ListView(children: [
          const HintBanner(id: 'more_tab', text: 'Everything else lives here: sync, messages, settings and (if you have access) admin tools.'),
          for (final d in items)
            ListTile(
              leading: Icon(d.icon),
              title: Text(d.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => d.build())),
            ),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Sign Out / Switch Account'), onTap: onSignOut),
        ]),
      );
}
