import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import 'backup_options.dart';
import 'cleanup_card.dart';
import 'job_detail_page.dart';
import 'job_widgets.dart';
import 'jobs_page.dart';
import 'snapshot_browser.dart';

/// Width below which the page uses the compact (phone) layout.
const double _kCompactWidth = 600;

/// Max content width of the phone-style single column.
const double _kMaxContentWidth = 920;

/// Max overall width of the two-pane desktop layout.
const double _kMaxWideWidth = 1280;

/// Width of the left sidebar on desktop.
const double _kSidebarWidth = 360;

/// Everything about one backup vault: browse, snapshots, jobs, schedules and maintenance.
class RepoPage extends ConsumerStatefulWidget {
  const RepoPage({super.key, required this.repoId, this.repo, this.initialTab = 0});
  final String repoId;
  final Point? repo;

  /// 0 = snapshots, 1 = jobs, 2 = schedules.
  final int initialTab;
  @override
  ConsumerState<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends ConsumerState<RepoPage> with SingleTickerProviderStateMixin {
  final _key = GlobalKey<CursorListState<Snapshot>>();
  final _cleanupKey = GlobalKey<CleanupCardState>();
  late final TabController _tc = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2).toInt());
  Point? _repo;
  Timer? _usageTimer;
  String? _jobStatus;
  Vaulton get _v => ref.read(vaultonProvider);

  void _setJobStatus(String? status) {
    if (_jobStatus == status) return;
    setState(() => _jobStatus = status);
  }

  @override
  void initState() {
    super.initState();
    _repo = widget.repo;
    _tc.addListener(() {
      if (!_tc.indexIsChanging && mounted) {
        setState(() {});
        _cleanupKey.currentState?.reload(); // schedules may have changed in the Schedules tab
      }
    });
    if (_repo == null) {
      _v.repo(widget.repoId).then((r) {
        if (mounted) setState(() => _repo = r);
      }).catchError((_) {});
    }
    _usageTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      try {
        final fresh = await _v.repo(widget.repoId);
        if (mounted) setState(() => _repo = fresh);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    _tc.dispose();
    super.dispose();
  }

  void _queued(RepoJob j) {
    toast(context, '${kindLabel(j.kind)} queued');
    Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)));
  }

  void _browse([Snapshot? s]) {
    final r = _repo;
    if (r == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: r, snapshotId: s?.id)));
  }

  Future<void> _backup() async {
    final repo = _repo;
    if (repo == null) return;
    final datas = await guarded(context, () => _v.datas(limit: 200));
    if (datas == null || !mounted) return;
    if (datas.items.isEmpty) return toast(context, 'Create a data folder first, then back it up here.', error: true);
    final req = await showBackupSheet(context, datas: datas.items, repos: [repo], repo: repo);
    if (req == null) return;
    final j = await guarded(context, () => _v.backup(widget.repoId, req.toBody()));
    if (j != null) _queued(j);
  }

  Future<void> _restore(Snapshot s) async {
    await restoreSnapshotFlow(
      context: context,
      vaulton: _v,
      repo: _repo!,
      snapshot: s,
    );
  }

  Future<void> _retention() async {
    final req = await showRetentionSheet(context);
    if (req == null) return;
    final j = await guarded(context, () => _v.retention(widget.repoId, req.policy, dryRun: req.dryRun));
    if (j != null) _queued(j);
  }

  Future<void> _healthCheck() async {
    final j = await guarded(context, () => _v.check(widget.repoId));
    if (j != null) _queued(j);
  }

  Future<void> _password() async {
    final f = await formDialog(context, 'Update vault password', [
      const FieldSpec('cur', 'Current password', kind: 'secret', required: true),
      const FieldSpec('new', 'New password (at least 8 characters)', kind: 'secret', required: true),
    ], intro: 'This only updates the password Vaulton uses to open this vault. It doesn’t change the vault’s encryption, so use it if the saved password is wrong.');
    if (f == null) return;
    await guarded(context, () => _v.changeRepoPassword(widget.repoId, f['cur']!, f['new']!));
    if (mounted) toast(context, 'Password updated');
  }

  /// Centers a sliver's content and caps its width (phone layout).
  Widget _centered(Widget child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child),
        ),
      );

  Widget _usageSection(Point r) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final pct = r.maxBytes > 0 ? (r.usedBytes / r.maxBytes * 100).round() : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Storage', style: tt.titleSmall)),
        chip(context, r.healthLabel, color: r.isError ? cs.errorContainer : null),
      ]),
      const SizedBox(height: 10),
      UsageBar(used: r.usedBytes, max: r.maxBytes),
      const SizedBox(height: 8),
      Row(children: [
        Text('${fmtBytes(r.usedBytes)} used', style: tt.bodyMedium),
        const Spacer(),
        Text('$pct% of ${fmtBytes(r.maxBytes)}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
      if (r.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(r.error!, style: TextStyle(color: cs.error, fontSize: 12)),
        ),
      const SizedBox(height: 16),
    ]);
  }
  Widget _header() {
    final r = _repo;

    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
    );
    Widget label(String t) => Text(t, maxLines: 1, overflow: TextOverflow.ellipsis);

    final backup = FilledButton.icon(
      style: style,
      onPressed: r == null ? null : _backup,
      icon: const Icon(Icons.backup_outlined, size: 18),
      label: label('Backup Now'),
    );
    final browse = FilledButton.tonalIcon(
      style: style,
      onPressed: r == null ? null : () => _browse(),
      icon: const Icon(Icons.folder_open, size: 18),
      label: label('Browse'),
    );
    final health = OutlinedButton.icon(
      style: style,
      onPressed: _healthCheck,
      icon: const Icon(Icons.fact_check_outlined, size: 18),
      label: label('Health Check'),
    );
    final cleanup = OutlinedButton.icon(
      style: style,
      onPressed: _retention,
      icon: const Icon(Icons.auto_delete_outlined, size: 18),
      label: label('Clean up'),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r != null) _usageSection(r),
            // Measure the space actually available inside the card's padding.
            LayoutBuilder(builder: (context, c) {
              if (c.maxWidth >= 460) {
                return Wrap(spacing: 8, runSpacing: 8, children: [backup, browse, health, cleanup]);
              }
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [Expanded(child: backup), const SizedBox(width: 8), Expanded(child: browse)]),
                const SizedBox(height: 8),
                Row(children: [Expanded(child: health), const SizedBox(width: 8), Expanded(child: cleanup)]),
              ]);
            }),
          ],
        ),
      ),
    );
  }
  
  Widget _snapshotCard(Snapshot s) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sum = s.summary;
    final locked = s.locked;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: locked ? cs.errorContainer.withValues(alpha: 0.45) : null,
      child: InkWell(
        onTap: () => _browse(s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: locked ? cs.error : cs.secondaryContainer,
              foregroundColor: locked ? cs.onError : cs.onSecondaryContainer,
              child: Icon(locked ? Icons.lock : Icons.camera_alt_outlined, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(fmtDate(s.time), style: t.titleMedium)),
                  if (locked) const SnapshotLockBadge(),
                ]),
                const SizedBox(height: 2),
                Text(shortId(s.id), style: t.bodySmall?.copyWith(color: cs.outline, fontFamily: 'monospace')),
                if (s.paths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(s.paths.join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                ],
                if (sum != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${fmtBytes(toInt(sum['totalBytesProcessed']))} · ${toInt(sum['totalFilesProcessed'])} files · +${fmtBytes(toInt(sum['bytesAdded']))} new',
                    style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                if (s.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(children: [for (final tg in s.tags) chip(context, '#$tg')]),
                ],
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (a) async {
                switch (a) {
                  case 'browse':
                    _browse(s);
                  case 'restore':
                    _restore(s);
                  case 'lock':
                    final r = await guarded(context, () => _v.lockSnapshot(widget.repoId, s.id, !s.locked));
                    if (r != null && mounted) toast(context, '${toStr(r['message']) ?? 'Done'} (the snapshot ID changed)');
                    _key.currentState?.refresh();
                  case 'copy':
                    copyText(context, s.id, 'Snapshot ID copied');
                  case 'forget':
                    if (await confirm(context, 'Delete snapshot?', 'Locked snapshots can’t be deleted. Space is only freed once you clean up old snapshots.', ok: 'Delete', danger: true)) {
                      final j = await guarded(context, () => _v.forget(widget.repoId, [s.id]));
                      if (j != null) _queued(j);
                    }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'browse', child: Text('Browse files')),
                const PopupMenuItem(value: 'restore', child: Text('Restore…')),
                PopupMenuItem(value: 'lock', child: Text(s.locked ? 'Unlock' : 'Lock')),
                const PopupMenuItem(value: 'copy', child: Text('Copy ID')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'forget', child: Text('Delete')),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  TabBar _tabs() {
    final wide = MediaQuery.sizeOf(context).width >= _kCompactWidth;
    return TabBar(
      controller: _tc,
      isScrollable: wide,
      tabAlignment: wide ? TabAlignment.start : TabAlignment.fill,
      dividerColor: wide ? Colors.transparent : null, // the wide layout draws its own divider
      tabs: const [Tab(text: 'Snapshots'), Tab(text: 'Jobs'), Tab(text: 'Schedules')],
    );
  }

  Widget _tabView() => TabBarView(controller: _tc, children: [
        CursorList<Snapshot>(
          key: _key,
          empty: 'No snapshots yet',
          emptyIcon: Icons.camera_alt_outlined,
          autoRefresh: const Duration(seconds: 5),
          fetch: (c) => _v.snapshots(widget.repoId, cursor: c),
          itemBuilder: (ctx, s, i) => _snapshotCard(s),
        ),
        JobsList(repoId: widget.repoId, externalStatus: _jobStatus, showFilters: false),
        SchedulesList(repoId: widget.repoId),
      ]);

  Widget _menu() => PopupMenuButton<String>(
        onSelected: (a) {
          if (a == 'pw') _password();
        },
        itemBuilder: (_) => const [PopupMenuItem(value: 'pw', child: Text('Update Vault Password…'))],
      );

  /// Desktop / tablet: sidebar with vault info and actions, main pane with tabs and the list.
  Widget _wideLayout() {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_repo?.name ?? 'Backup Vault', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [_menu()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWideWidth),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: _kSidebarWidth,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                children: [
                  _header(),
                  CleanupCard(key: _cleanupKey, repoId: widget.repoId, onRunNow: _retention),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: cs.outlineVariant),
            Expanded(
              child: Column(children: [
                DecoratedBox(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
                  child: Align(alignment: Alignment.centerLeft, child: _tabs()),
                ),
                if (_tc.index == 1) _JobFilters(status: _jobStatus, onChanged: _setJobStatus),
                Expanded(child: _tabView()),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < _kCompactWidth;
    if (!compact) return _wideLayout();

    final jobs = _tc.index == 1;
    return Scaffold(
      floatingActionButton: _tc.index == 0
          ? FloatingActionButton.extended(onPressed: _backup, icon: const Icon(Icons.backup), label: const Text('Backup'))
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // A real AppBar: back button, title and menu spacing match every other screen.
          SliverAppBar(
            title: Text(_repo?.name ?? 'Backup Vault', maxLines: 1, overflow: TextOverflow.ellipsis),
            floating: true,
            snap: true,
            scrolledUnderElevation: 0,
            actions: [_menu()],
          ),
          SliverToBoxAdapter(child: _centered(_header())),
          SliverToBoxAdapter(
            child: _centered(CleanupCard(key: _cleanupKey, repoId: widget.repoId, onRunNow: _retention)),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverPersistentHeader(pinned: true, delegate: _PinnedTabBarDelegate(_tabs())),
          if (jobs)
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedJobFiltersDelegate(
                _JobFilters(status: _jobStatus, onChanged: _setJobStatus),
              ),
            ),
        ],
        body: _tabView(),
      ),
    );
  }
}

class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedTabBarDelegate(this.child);
  final TabBar child;

  @override
  double get minExtent => child.preferredSize.height;

  @override
  double get maxExtent => child.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 2 : 0,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedTabBarDelegate oldDelegate) => true;
}

class _PinnedJobFiltersDelegate extends SliverPersistentHeaderDelegate {
  _PinnedJobFiltersDelegate(this.child);
  final Widget child;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 2 : 0,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedJobFiltersDelegate oldDelegate) => oldDelegate.child != child;
}

const _jobStatusFilters = <(String label, String? value)>[
  ('All', null),
  ('Running', 'Running'),
  ('Waiting', 'Pending'),
  ('Succeeded', 'Succeeded'),
  ('Failed', 'Failed'),
  ('Cancelled', 'Cancelled'),
];

class _JobFilters extends StatelessWidget {
  const _JobFilters({required this.status, required this.onChanged});
  final String? status;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          children: [
            for (final f in _jobStatusFilters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.$1),
                  selected: status == f.$2,
                  onSelected: (_) => onChanged(f.$2),
                ),
              ),
          ],
        ),
      );
}