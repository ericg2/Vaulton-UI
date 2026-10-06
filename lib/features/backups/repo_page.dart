import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  Widget _header() {
    final r = _repo;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _kCompactWidth;
        final pad = compact ? 12.0 : 20.0;
        final gap = compact ? 8.0 : 12.0;

        final buttons = <Widget>[
          FilledButton.icon(
            onPressed: r == null ? null : () => _browse(),
            icon: const Icon(Icons.folder_open),
            label: const Text('Browse'),
          ),
          FilledButton.tonalIcon(
            onPressed: _backup,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Backup Now'),
          ),
          OutlinedButton.icon(
            onPressed: _healthCheck,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Health Check'),
          ),
          OutlinedButton.icon(
            onPressed: _retention,
            icon: const Icon(Icons.auto_delete_outlined),
            label: const Text('Clean up'),
          ),
        ];

        Widget usage() {
          if (r == null) return const SizedBox.shrink();
          final label = Text('${fmtBytes(r.usedBytes)} of ${fmtBytes(r.maxBytes)}', style: tt.labelMedium);
          final health = chip(context, r.healthLabel, color: r.isError ? cs.errorContainer : null);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (compact) ...[
              UsageBar(used: r.usedBytes, max: r.maxBytes),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: label),
                health,
              ]),
            ] else
              Row(children: [
                Expanded(child: UsageBar(used: r.usedBytes, max: r.maxBytes)),
                const SizedBox(width: 16),
                label,
                const SizedBox(width: 12),
                health,
              ]),
            if (r.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(r.error!, style: TextStyle(color: cs.error, fontSize: 12)),
              ),
            SizedBox(height: gap + 4),
          ]);
        }

        Widget actions() {
          if (!compact) return Wrap(spacing: gap, runSpacing: gap, children: buttons);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: buttons[0]),
              SizedBox(width: gap),
              Expanded(child: buttons[1]),
            ]),
            SizedBox(height: gap),
            Row(children: [
              Expanded(child: buttons[2]),
              SizedBox(width: gap),
              Expanded(child: buttons[3]),
            ]),
          ]);
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Card(
              margin: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 4),
              child: Padding(
                padding: EdgeInsets.all(pad),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [usage(), actions()],
                ),
              ),
            ),
          ),
        );
      },
    );
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
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s.locked ? Icons.lock_outline : Icons.camera_alt_outlined, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtDate(s.time), style: t.titleMedium),
                  Text(shortId(s.id), style: t.bodySmall?.copyWith(color: cs.outline, fontFamily: 'monospace')),
                ]),
              ),
              PopupMenuButton<String>(
                onSelected: (a) async {
                  switch (a) {
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
                  const PopupMenuItem(value: 'restore', child: Text('Restore…')),
                  PopupMenuItem(value: 'lock', child: Text(s.locked ? 'Unlock' : 'Lock')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy ID')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'forget', child: Text('Delete')),
                ],
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4, right: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (s.paths.isNotEmpty) Text(s.paths.join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                if (sum != null) Text('${fmtBytes(toInt(sum['totalBytesProcessed']))} · ${toInt(sum['totalFilesProcessed'])} files · +${fmtBytes(toInt(sum['bytesAdded']))} new', style: t.bodySmall),
                if (s.tags.isNotEmpty) Wrap(children: [for (final tg in s.tags) chip(context, '#$tg')]),
              ]),
            ),
            OverflowBar(alignment: MainAxisAlignment.start, children: [
              TextButton.icon(onPressed: () => _browse(s), icon: const Icon(Icons.folder_open), label: const Text('Browse Files')),
              TextButton.icon(onPressed: () => _restore(s), icon: const Icon(Icons.settings_backup_restore), label: const Text('Restore…')),
            ]),
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
      
  Widget _topBar() {
    final canPop = Navigator.of(context).canPop();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(children: [
            // Same 56px leading slot AppBar uses, so the arrow lines up with other screens.
            if (canPop)
              SizedBox(
                width: 56,
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              )
            else
              const SizedBox(width: 16),
            Expanded(
              child: Text(
                _repo?.name ?? 'Backup Vault',
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (a) {
                if (a == 'pw') _password();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'pw', child: Text('Update Vault Password…'))],
            ),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }

  Widget _cleanup() => CleanupCard(
        key: _cleanupKey,
        repoId: widget.repoId,
        onRunNow: _retention,
      );

  @override
  Widget build(BuildContext context) {
    final jobs = _tc.index == 1;
    final compact = MediaQuery.sizeOf(context).width < _kCompactWidth;

    // Wide screens: nothing collapses, it all just scrolls. Only the tab bar stays pinned.
    // Phones: the top bar, vault card and cleanup card fade away to save space.
    final topSlivers = compact
        ? <Widget>[
            SliverPersistentHeader(
              pinned: false,
              delegate: _CollapsingTopBarDelegate(
                _topBar(),
                kToolbarHeight + MediaQuery.paddingOf(context).top,
              ),
            ),
            SliverPersistentHeader(pinned: true, delegate: _PinnedTabBarDelegate(_tabs())),
            _AutoHeightHeader(initialHeight: 190, child: _header()),
            _AutoHeightHeader(initialHeight: 156, child: _cleanup()),
          ]
        : <Widget>[
            SliverToBoxAdapter(child: _topBar()),
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
                  child: _cleanup(),
                ),
              ),
            ),
            SliverPersistentHeader(pinned: true, delegate: _PinnedTabBarDelegate(_tabs())),
          ];

    return Scaffold(
      // On wide screens "Backup Now" is already in the header, so the FAB is phone-only.
      floatingActionButton: (_tc.index == 0 && compact)
          ? FloatingActionButton.extended(onPressed: _backup, icon: const Icon(Icons.backup), label: const Text('Backup'))
          : null,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          ...topSlivers,
          if (jobs)
            SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedJobFiltersDelegate(
                _JobFilters(
                  status: _jobStatus,
                  onChanged: _setJobStatus,
                ),
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

/// A collapsing (fade + slide) sliver header whose height follows its child's
/// real height, instead of a hardcoded extent. Used on phones only.
class _AutoHeightHeader extends StatefulWidget {
  const _AutoHeightHeader({required this.child, this.initialHeight = 0});
  final Widget child;

  /// Used only until the child has been measured once.
  final double initialHeight;

  @override
  State<_AutoHeightHeader> createState() => _AutoHeightHeaderState();
}

class _AutoHeightHeaderState extends State<_AutoHeightHeader> {
  late double _height = widget.initialHeight;

  void _onMeasured(double h) {
    if (!mounted || (h - _height).abs() < 0.5) return;
    setState(() => _height = h);
  }

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: false,
      delegate: _AutoHeightDelegate(widget.child, _height, _onMeasured),
    );
  }
}

class _AutoHeightDelegate extends SliverPersistentHeaderDelegate {
  _AutoHeightDelegate(this.child, this.extent, this.onMeasured);
  final Widget child;
  final double extent;
  final ValueChanged<double> onMeasured;

  @override
  double get minExtent => 0;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = extent <= 0 ? 0.0 : (shrinkOffset / extent).clamp(0, 1).toDouble();
    return ClipRect(
      child: Opacity(
        opacity: 1 - progress,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1 - progress,
          child: Transform.translate(
            offset: Offset(0, -20 * progress),
            // Let the child take its natural height, and report it.
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: _MeasureSize(onChange: onMeasured, child: child),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AutoHeightDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.extent != extent;
}

/// Reports its child's height after layout.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget super.child});
  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderMeasureSize renderObject) {
    renderObject.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);
  ValueChanged<double> onChange;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(h));
  }
}

class _CollapsingTopBarDelegate extends SliverPersistentHeaderDelegate {
  _CollapsingTopBarDelegate(this.child, this.extent);
  final Widget child;
  final double extent;

  @override
  double get minExtent => 0;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final progress = (shrinkOffset / maxExtent).clamp(0, 1).toDouble();
    return ClipRect(
      child: Opacity(
        opacity: 1 - progress,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1 - progress,
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingTopBarDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.extent != extent;
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