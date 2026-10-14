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
  String? _selectedLabel = 'Dashboard';
  bool _wasWide = true;
  int _storageTab = 0;
  final _visited = <int>{0};
  final PageController _pages = PageController();
  late final AppLifecycleListener _life;

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
          content: const Text('Minimise Vaulton to keep transfers running, or quit and resume them next time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Quit')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Minimise')),
          ],
        ),
      );
      return r ?? true;
    });
  }


  @override
  void dispose() {
    _life.dispose();
    clearCloseGuard();
    _pages.dispose();
    super.dispose();
  }

  // Phone pages: 0 Dashboard, 1 Files, 2 Transfers, 3-5 Storage tabs, 6 More.
  int _pageForNav(int nav) => nav < 3 ? nav : (nav == 3 ? 3 + _storageTab : 6);
  int _navForPage(int page) => page < 3 ? page : (page < 6 ? 3 : 4);

  /// Switches tab. On phones the page slides, so taps and swipes feel the same.
  void _select(int i, {String? label, bool isMore = false}) {
    final from = _index;
    setState(() {
      _index = i;
      _selectedLabel = isMore ? null : label;
      _visited.add(i);
    });
    if (_pages.hasClients && from != i) _animateToPage(_pageForNav(i));
  }

  void _animateToPage(int target) {
    final current = (_pages.page ?? target.toDouble()).round();
    if (current == target) return;
    if ((target - current).abs() > 1) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    }
  }

  void _selectStorageTab(int sub) {
    _storageTab = sub;
    if (_pages.hasClients) _animateToPage(3 + sub);
  }

  void _goto(String label, List<_Dest> dests, bool wide) {
    if (label == 'Data Folders' || label == 'Backup Vaults') {
      _storageTab = label == 'Data Folders' ? 0 : 1;
      final storage = dests.indexWhere((d) => d.label == 'Storage');
      if (storage >= 0) {
        if (wide) {
          _select(storage, label: dests[storage].label);
        } else if (_index == storage) {
          _selectStorageTab(_storageTab);
        } else {
          _select(storage, label: dests[storage].label);
        }
      }
      return;
    }
    final i = dests.indexWhere((d) => d.label == label);
    if (i < 0) return;
    if (wide || i < 4) {
      _select(i, label: dests[i].label);
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => dests[i].build()));
    }
  }

  List<_Dest> _dests(UserAccount u, bool wide) => [
        _Dest('Dashboard', Icons.dashboard_outlined, Icons.dashboard, () => DashboardPage(onNavigate: (l) => _goto(l, _dests(ref.read(userProvider)!, wide), wide))),
        _Dest('Files', Icons.folder_outlined, Icons.folder, () => const FilesPage()),
        _Dest('Transfers', Icons.swap_vert, Icons.swap_vert, () => const TransfersPage()),
        _Dest('Storage', Icons.storage_outlined, Icons.storage, () => StoragePage(key: ValueKey(_storageTab), initialTab: _storageTab)),
        if (u.has(Scopes.jobsManage)) _Dest('Activity', Icons.history_outlined, Icons.history, () => const BackupsPage()),
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

  void _openMoreDestination(_Dest d) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => d.build()));
  }

  Widget _withAndroidBack(Widget child) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          _select(0, label: 'Dashboard');
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

    final selectedDestination = _selectedLabel == null ? null : dests.indexWhere((d) => d.label == _selectedLabel);
    final effectiveIndex = wide
        ? (selectedDestination != null && selectedDestination >= 0 ? selectedDestination : _index.clamp(0, dests.length - 1).toInt())
        : (selectedDestination != null && selectedDestination >= 0 && selectedDestination < 4 ? selectedDestination : 4);

    // Resized from a wide layout to a phone layout: land on the matching page.
    if (!wide && _wasWide) {
      final target = _pageForNav(effectiveIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(target);
      });
    }
    _wasWide = wide;

    Widget body(int i) => _visited.contains(i) ? dests[i].build() : const SizedBox.shrink();

    if (wide) {
      return _withAndroidBack(Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: extended,
            selectedIndex: effectiveIndex,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            onDestinationSelected: (i) => _select(i, label: dests[i].label),
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
          Expanded(child: _FadeIndexed(index: effectiveIndex, children: [for (var i = 0; i < dests.length; i++) body(i)])),
        ]),
      ));
    }

    // Phones: 4 main tabs plus "More". Pages slide with your finger and snap into place.
    final primary = dests.take(4).toList();
    final rest = dests.skip(4).toList();
    final onMore = effectiveIndex == 4;
    return _withAndroidBack(Scaffold(
      body: Stack(children: [
        Positioned.fill(child: PageView(
        controller: _pages,
        onPageChanged: (page) {
          final nav = _navForPage(page);
          setState(() {
            _index = nav;
            if (page >= 3 && page <= 5) _storageTab = page - 3;
            _selectedLabel = nav < primary.length ? primary[nav].label : null;
            _visited.add(nav);
          });
        },
        children: [
          for (var i = 0; i < 3; i++) _KeepAlive(child: dests[i].build()),
          for (var i = 0; i < 3; i++)
            _KeepAlive(child: StorageSection(index: i)),
          _KeepAlive(child: _MorePage(items: rest, onSignOut: () => signOutFlow(context, ref), onOpen: _openMoreDestination)),
        ],
      )),
        Positioned(top: 0, left: 0, right: 0, child: StorageHeader(pages: _pages, basePage: 3, onSelect: _selectStorageTab)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: effectiveIndex,
        onDestinationSelected: (i) => _select(i, label: i < primary.length ? primary[i].label : null, isMore: i == 4),
        destinations: [
          for (final d in primary)
            NavigationDestination(icon: _icon(d, false, unread, active), selectedIcon: _icon(d, true, unread, active), label: d.label),
          NavigationDestination(icon: Icon(onMore ? Icons.apps : Icons.apps_outlined), label: 'More'),
        ],
      ),
    ));
  }
}

/// Keeps a page alive once built, so scroll position and loaded data survive swiping away.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 160), value: 1);
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
  const _MorePage({required this.items, required this.onSignOut, required this.onOpen});
  final List<_Dest> items;
  final VoidCallback onSignOut;
  final void Function(_Dest) onOpen;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('More')),
        body: ListView(children: [
          const HintBanner(id: 'more_tab', text: 'Sync, messages, settings and admin tools.'),
          for (final d in items)
            ListTile(
              leading: Icon(d.icon),
              title: Text(d.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(d),
            ),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Sign Out or Switch Account'), onTap: onSignOut),
        ]),
      );
}
