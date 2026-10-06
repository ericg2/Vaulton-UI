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

/// Max content width on large screens.
const double _kMaxContentWidth = 920;

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

  /// Centers a sliver's content and caps its width on large screens.
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
    return LayoutBuilder(builder: (context, constraints) {
      // The card's own padding (16 + 16) is already excluded from what the buttons see.
      final compact = constraints.maxWidth < _kCompactWidth;

      final backup = FilledButton.icon(
        onPressed: r == null ? null : _backup,
        icon: const Icon(Icons.backup_outlined),
        label: const Text('Backup Now'),
      );
      final browse = FilledButton.tonalIcon(
        onPressed: r == null ? null : () => _browse(),
        icon: const Icon(Icons.folder_open),
        label: const Text('Browse'),
      );
      final health = OutlinedButton.icon(
        onPressed: _healthCheck,
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Health Check'),
      );
      final cleanup = OutlinedButton.icon(
        onPressed: _retention,
        icon: const Icon(Icons.auto_delete_outlined),
        label: const Text('Clean up'),
      );

      final actions = compact
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [Expanded(child: backup), const SizedBox(width: 8), Expanded(child: browse)]),
              const SizedBox(height: 8),
              Row(children: [Expanded(child: health), const SizedBox(width: 8), Expanded(child: cleanup)]),
            ])
          : Wrap(spacing: 8, runSpacing: 8, children: [backup, browse, health, cleanup]);

      return Card(
        child: Padding(
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r != null) _usageSection(r),
              actions,
            ],
          ),
        ),
      );
    });
  }

  Widget _snapshotCard(Snapshot s) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final sum = s.summary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _browse(s),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
              child: Icon(s.locked ? Icons.lock_outline : Icons.camera_alt_outlined, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fmtDate(s.time), style: t.titleMedium),
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

  TabBar _tabs() => TabBar(controller: _tc, tabs: const [Tab(text: 'Snapshots'), Tab(text: 'Jobs'), Tab(text: 'Schedules')]);

  Widget _tabView() => TabBarView(controller: _tc, children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: CursorList<Snapshot>(
              key: _key,
              empty: 'No snapshots yet',
              emptyIcon: Icons.camera_alt_outlined,
              autoRefresh: const Duration(seconds: 5),
              fetch: (c) => _v.snapshots(widget.repoId, cursor: c),
              itemBuilder: (ctx, s, i) => _snapshotCard(s),
            ),
          ),
        ),
        JobsList(repoId: widget.repoId, externalStatus: _jobStatus, showFilters: false),
        SchedulesList(repoId: widget.repoId),
      ]);

  @override
  Widget build(BuildContext context) {
    final jobs = _tc.index == 1;
    final compact = MediaQuery.sizeOf(context).width < _kCompactWidth;

    return Scaffold(
      // On wide screens "Backup Now" is already in the header, so the FAB is phone-only.
      floatingActionButton: (_tc.index == 0 && compact)
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
            actions: [
              PopupMenuButton<String>(
                onSelected: (a) {
                  if (a == 'pw') _password();
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'pw', child: Text('Update Vault Password…'))],
              ),
            ],
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
  bool shouldRebuild(covariant _PinnedTabBarDelegate oldDelegate) => false;
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