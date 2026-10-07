import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import 'job_detail_page.dart';
import 'job_text.dart';
import 'job_widgets.dart';
import 'snapshot_browser.dart';

/// One row of vault history: a job, the snapshot it produced, or both joined.
class TimelineEntry {
  TimelineEntry({this.job, this.snap});
  final RepoJob? job;
  final Snapshot? snap;

  DateTime get time =>
      job?.startDate ?? job?.scheduleDate ?? job?.createdAt ?? snap?.time ?? DateTime.fromMillisecondsSinceEpoch(0);
}

bool _idMatch(String a, String b) => a == b || (a.length >= 6 && b.length >= 6 && (a.startsWith(b) || b.startsWith(a)));

/// Joins jobs and snapshots into one newest-first list.
///  1. Backup job <-> snapshot by id (full id or prefix, either direction).
///  2. Leftovers pair by time: the snapshot time falls inside the job's run window.
///     (Locking rewrites a snapshot and changes its id, which breaks step 1.)
///  3. Everything still unpaired is shown on its own.
List<TimelineEntry> buildTimeline(Iterable<RepoJob> jobs, Iterable<Snapshot> snaps) {
  final jobList = jobs.toList();
  final snapList = snaps.toList();
  final used = <String>{};
  final pairs = <String, Snapshot>{};

  for (final j in jobList.where((j) => j.kind == 'backup' && j.snapshotId != null && j.snapshotId!.isNotEmpty)) {
    final s = snapList.where((s) => !used.contains(s.id) && _idMatch(s.id, j.snapshotId!)).firstOrNull;
    if (s != null) {
      pairs[j.id] = s;
      used.add(s.id);
    }
  }
  final orphans = jobList
      .where((j) => j.kind == 'backup' && !pairs.containsKey(j.id) && j.phase == JobPhase.succeeded && j.options['dryRun'] != true && j.startDate != null)
      .toList();
  for (final s in snapList.where((s) => !used.contains(s.id))) {
    final st = s.time;
    if (st == null) continue;
    RepoJob? best;
    Duration? bestD;
    for (final j in orphans) {
      if (pairs.containsKey(j.id)) continue;
      final from = j.startDate!.subtract(const Duration(minutes: 2));
      final to = (j.endDate ?? DateTime.now()).add(const Duration(minutes: 2));
      if (st.isBefore(from) || st.isAfter(to)) continue;
      final d = st.difference(j.startDate!).abs();
      if (bestD == null || d < bestD) {
        best = j;
        bestD = d;
      }
    }
    if (best != null) {
      pairs[best.id] = s;
      used.add(s.id);
    }
  }
  return <TimelineEntry>[
    for (final j in jobList) TimelineEntry(job: j, snap: pairs[j.id]),
    for (final s in snapList) if (!used.contains(s.id)) TimelineEntry(snap: s),
  ]..sort((a, b) => b.time.compareTo(a.time));
}

const _filters = ['Backups', 'Other Activity', 'Failed', 'All'];
const _snapshotFilters = ['All', 'Locked', 'Unlocked'];

class _TimelineFilterDelegate extends SliverPersistentHeaderDelegate {
  const _TimelineFilterDelegate(this.child);
  final Widget child;
  @override double get minExtent => 52;
  @override double get maxExtent => 52;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;
    return Material(color: cs.surface, elevation: overlapsContent ? 2 : 0, child: child);
  }
  @override
  bool shouldRebuild(covariant _TimelineFilterDelegate oldDelegate) => true;
}

/// The "History" tab. Backups come first by default; restores, cleanups and
/// health checks live under "Other activity".
class VaultTimeline extends ConsumerStatefulWidget {
  const VaultTimeline({super.key, required this.repoId, required this.repo, required this.onBackup, this.header, this.showFab = true, this.snapshotOnly = false});
  final String repoId;
  final Point? repo;
  final VoidCallback onBackup;
  final Widget? header;
  final bool showFab;
  final bool snapshotOnly;
  @override
  ConsumerState<VaultTimeline> createState() => _VaultTimelineState();
}

class _VaultTimelineState extends ConsumerState<VaultTimeline> {
  final Map<String, RepoJob> _jobs = {};
  final Map<String, Snapshot> _snaps = {};
  String? _jobCursor, _snapCursor;
  bool _jobMore = false, _snapMore = false, _paged = false;
  bool _loading = true, _loadingMore = false;
  Object? _error;
  int _filter = 0;
  final Set<String> _locking = {};
  Timer? _timer;
  Vaulton get _v => ref.read(vaultonProvider);

  @override
  void initState() {
    super.initState();
    _load(spinner: true, replace: true);
    var tick = 0;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      tick++;
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      if (_jobs.values.any((j) => j.active) || tick % 6 == 0) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool spinner = false, bool replace = false}) async {
    if (spinner) setState(() { _loading = true; _error = null; });
    try {
      final r = await Future.wait([_v.jobs(repoId: widget.repoId, limit: 100), _v.snapshots(widget.repoId, limit: 100)]);
      final jp = r[0] as Paged<RepoJob>;
      final sp = r[1] as Paged<Snapshot>;
      if (!mounted) return;
      setState(() {
        if (replace || !_paged) {
          _jobs.clear();
          _snaps.clear();
          _jobCursor = jp.nextCursor;
          _jobMore = jp.hasMore;
          _snapCursor = sp.nextCursor;
          _snapMore = sp.hasMore;
          _paged = false;
        }
        for (final j in jp.items) { _jobs[j.id] = j; }
        for (final s in sp.items) { _snaps[s.id] = s; }
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && (spinner || _jobs.isEmpty)) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _more() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final jp = _jobMore ? await _v.jobs(repoId: widget.repoId, cursor: _jobCursor, limit: 100) : null;
      final sp = _snapMore ? await _v.snapshots(widget.repoId, cursor: _snapCursor, limit: 100) : null;
      if (!mounted) return;
      setState(() {
        _paged = true;
        if (jp != null) {
          for (final j in jp.items) { _jobs[j.id] = j; }
          _jobCursor = jp.nextCursor;
          _jobMore = jp.hasMore;
        }
        if (sp != null) {
          for (final s in sp.items) { _snaps[s.id] = s; }
          _snapCursor = sp.nextCursor;
          _snapMore = sp.hasMore;
        }
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool _match(TimelineEntry e) {
    final j = e.job;
    if (widget.snapshotOnly) {
      final s = e.snap;
      if (s == null) return false;
      switch (_filter) {
        case 1: return s.locked;
        case 2: return !s.locked;
        default: return true;
      }
    }
    switch (_filter) {
      case 0: return e.snap != null || j?.kind == 'backup';
      case 1: return j != null && j.kind != 'backup';
      case 2: return j?.phase == JobPhase.failed;
      default: return true;
    }
  }

  // ------------------------------------------------------------- actions
  void _browse(String snapshotId) {
    final r = widget.repo;
    if (r == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: r, snapshotId: snapshotId)));
  }

  Future<void> _openJob(RepoJob j) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id, showVaultLink: false)));
    if (mounted) _load(replace: true);
  }

  Future<void> _menu(String a, Snapshot s) async {
    if (a == 'browse') {
      _browse(s.id);
    } else if (a == 'restore') {
      final r = widget.repo;
      if (r == null) return;
      await restoreSnapshotFlow(context: context, vaulton: _v, repo: r, snapshot: s);
      ref.read(epochProvider.notifier).bump();
    } else if (a == 'lock') {
      if (_locking.contains(s.id)) return;
      setState(() => _locking.add(s.id));
      try {
        final r = await guarded(context, () => _v.lockSnapshot(widget.repoId, s.id, !s.locked));
        if (r != null && mounted) toast(context, toStr(r['message']) ?? (s.locked ? 'Snapshot unlocked' : 'Snapshot locked'));
        await _load(replace: true);
      } finally {
        if (mounted) setState(() => _locking.remove(s.id));
      }
    } else if (a == 'copy') {
      copyText(context, s.id, 'Snapshot ID copied');
    } else if (a == 'forget') {
      if (!await confirm(context, 'Delete snapshot?', 'Locked snapshots can’t be deleted. Space is only freed once old snapshots are cleaned up.', ok: 'Delete', danger: true)) return;
      final j = await guarded(context, () => _v.forget(widget.repoId, [s.id]));
      if (j != null && mounted) await _openJob(j);
    }
  }

  // --------------------------------------------------------------- build
  Widget _filterBar() => SizedBox(
        height: 52,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), children: [
          for (var i = 0; i < (widget.snapshotOnly ? _snapshotFilters : _filters).length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(widget.snapshotOnly ? _snapshotFilters[i] : _filters[i]), selected: _filter == i, onSelected: (_) => setState(() => _filter = i)),
            ),
        ]),
      );

  /// Shown on the Backups view while a cleanup / check / restore is running.
  Widget _activityBanner(RepoJob j) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: InkWell(
        onTap: () => setState(() => _filter = 1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text('${kindLabel(j.kind)} ${j.phase == JobPhase.waiting ? 'waiting' : 'running'}…', style: TextStyle(color: cs.onTertiaryContainer))),
            Text('View', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String text, {Color? bg, Color? fg, bool mono = false}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg ?? cs.secondaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg ?? cs.onSecondaryContainer, fontFamily: mono ? 'monospace' : null)),
    );
  }

  Widget _card(TimelineEntry e, Map<String, String> names) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final j = widget.snapshotOnly ? null : e.job, s = e.snap;
    final phase = j?.phase ?? JobPhase.succeeded;
    final st = phaseStyle(context, phase);
    final dry = j?.options['dryRun'] == true;
    final isBackup = j == null || j.kind == 'backup';
    final okBackup = j != null && isBackup && phase == JobPhase.succeeded && !dry;
    final title = j == null ? 'Backup' : '${kindLabel(j.kind)}${dry ? ' · test run' : ''}';
    final dur = j?.duration;
    final meta = [
      fmtDate(e.time),
      if (j != null) (j.scheduleId != null ? 'Scheduled' : 'Manual'),
      if (dur != null) fmtDuration(dur),
    ].join('  ·  ');

    // Snapshot to browse: the paired one, or the id the job recorded (the browser resolves it).
    final browseId = s?.id ?? (okBackup && (j.snapshotId?.isNotEmpty ?? false) ? j.snapshotId : null);

    String? what;
    if (j != null) {
      if (isBackup) {
        final dn = j.dataId == null ? null : names[j.dataId!];
        what = '${dn != null ? '$dn · ' : ''}${j.options['path'] ?? '/'}';
      } else {
        what = jobSummary(j);
      }
    } else if (s != null && s.paths.isNotEmpty) {
      what = s.paths.join(', ');
    }
    final sum = s?.summary;
    final result = sum == null
        ? (okBackup ? '0 files · 0 MB new' : null)
        : '${fmtBytes(toInt(sum['totalBytesProcessed']))} · ${toInt(sum['totalFilesProcessed'])} files · +${fmtBytes(toInt(sum['bytesAdded']))} new';
    String? note;
    if (j == null) note = 'No job record for this snapshot.';
    if (okBackup && browseId == null) note = 'This run did not record a snapshot.';
    final err = cleanJobError(j?.error);
    final indent = MediaQuery.sizeOf(context).width >= 600 ? 52.0 : 0.0;

    final pills = <Widget>[
      if (browseId != null) _pill('Snapshot ${shortId(browseId)}', mono: true),
      if (s != null && s.locked) const SnapshotLockBadge(),
      if (s != null) for (final tg in s.tags) _pill('#$tg'),
    ];

    return Card(
      child: InkWell(
        onTap: j != null ? () => _openJob(j) : (browseId != null ? () => _browse(browseId) : null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: st.bg, shape: BoxShape.circle),
                child: Icon(j == null ? Icons.camera_alt_outlined : kindIcon(j.kind), color: st.fg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(meta, style: t.bodySmall?.copyWith(color: cs.outline), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (j != null) ...[const SizedBox(width: 8), StatusPill(phase)],
              if (s != null && _locking.contains(s.id))
                const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              else if (s != null)
                PopupMenuButton<String>(
                  onSelected: (a) => _menu(a, s),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'browse', child: Text('Browse Files')),
                    const PopupMenuItem(value: 'restore', child: Text('Restore…')),
                    PopupMenuItem(value: 'lock', child: Text(s.locked ? 'Unlock' : 'Lock')),
                    const PopupMenuItem(value: 'copy', child: Text('Copy snapshot ID')),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'forget', child: Text('Delete snapshot')),
                  ],
                )
              else
                const SizedBox(width: 12),
            ]),
            Padding(
              padding: EdgeInsets.fromLTRB(indent, 10, 12, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (what != null && what.isNotEmpty) Text(what, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (result != null) ...[const SizedBox(height: 4), Text(result, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant))],
                if (note != null) ...[const SizedBox(height: 4), Text(note, style: t.bodySmall?.copyWith(color: cs.outline))],
                if (j != null && phase == JobPhase.running) ...[
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: j.liveFraction, minHeight: 6)),
                ],
                if (j != null && phase == JobPhase.waiting && j.scheduleDate != null) ...[
                  const SizedBox(height: 4),
                  Text('Starts ${fmtDate(j.scheduleDate)}', style: t.bodySmall?.copyWith(color: cs.outline)),
                ],
                if (err.isNotEmpty) ...[const SizedBox(height: 6), Text(err, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.error))],
                if (pills.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 6, runSpacing: 6, children: pills)],
                if (browseId != null || j != null) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 0, children: [
                    if (browseId != null && widget.repo != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => _browse(browseId),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Browse Files'),
                      ),
                    if (j != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id, showVaultLink: false, initialTab: 1))),
                        icon: const Icon(Icons.notes, size: 18),
                        label: const Text('Job Log'),
                      ),
                  ]),
                ] else
                  const SizedBox(height: 4),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(epochProvider, (_, _) => _load());
    final names = ref.watch(pointNamesProvider).value ?? const <String, String>{};
    final all = buildTimeline(_jobs.values, _snaps.values);
    final entries = all.where(_match).toList();
    final hasHeader = widget.header != null;
    final more = _jobMore || _snapMore;
    final busy = !widget.snapshotOnly && _filter == 0 ? _jobs.values.where((j) => j.active && j.kind != 'backup').firstOrNull : null;

    Widget emptySlot() {
      if (_loading) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
      if (_error != null && all.isEmpty) return SizedBox(height: 260, child: ErrorView(_error!, onRetry: () => _load(spinner: true, replace: true)));
      final msg = all.isEmpty
          ? (widget.snapshotOnly ? 'No snapshots yet' : 'No history yet')
          : (widget.snapshotOnly ? (_filter == 1 ? 'No locked snapshots' : (_filter == 2 ? 'No unlocked snapshots' : 'No snapshots yet')) : (_filter == 0 ? 'No backups yet' : (_filter == 1 ? 'No other activity' : 'Nothing failed')));
      return SizedBox(
        height: 220,
        child: EmptyView(msg, icon: Icons.history, hint: all.isEmpty ? 'Run a backup and it will show up here, together with its snapshot.' : null),
      );
    }

    // [header?] [filters] [banner?] [entries or empty] [footer]
    return Scaffold(
      floatingActionButton: widget.showFab
          ? FloatingActionButton.extended(onPressed: widget.onBackup, icon: const Icon(Icons.backup_outlined), label: const Text('Backup now'))
          : null,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: RefreshIndicator(
            onRefresh: () => _load(replace: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (hasHeader) SliverToBoxAdapter(child: widget.header!),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TimelineFilterDelegate(_filterBar()),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (c, i) {
                      if (busy != null) {
                        if (i == 0) return _activityBanner(busy);
                        i--;
                      }
                      if (entries.isEmpty) {
                        if (i == 0) return emptySlot();
                        i--;
                      } else {
                        if (i < entries.length) return _card(entries[i], names);
                        i -= entries.length;
                      }
                      if (more) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          child: Center(
                            child: _loadingMore
                                ? const CircularProgressIndicator(strokeWidth: 2)
                                : TextButton.icon(onPressed: _more, icon: const Icon(Icons.expand_more), label: Text(widget.snapshotOnly ? 'Load older snapshots' : 'Load older history')),
                          ),
                        );
                      }
                      return const SizedBox(height: 96);
                    },
                    childCount: (busy != null ? 1 : 0) + (entries.isEmpty ? 1 : entries.length) + 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
