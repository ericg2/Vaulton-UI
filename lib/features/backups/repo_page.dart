import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../files/folder_picker.dart';
import 'job_detail_page.dart';
import 'job_widgets.dart';
import 'jobs_page.dart';
import 'snapshot_browser.dart';

/// Everything about one repository: browse, snapshots, jobs, schedules and maintenance.
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
  late final TabController _tc = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2).toInt());
  Point? _repo;
  Timer? _usageTimer;
  Vaulton get _v => ref.read(vaultonProvider);

  @override
  void initState() {
    super.initState();
    _repo = widget.repo;
    _tc.addListener(() {
      if (!_tc.indexIsChanging && mounted) setState(() {});
    });
    if (_repo == null) {
      _v.repo(widget.repoId).then((r) {
        if (mounted) setState(() => _repo = r);
      }).catchError((_) {});
    }
    _usageTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || !TickerMode.of(context)) return;
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
    final datas = await guarded(context, () => _v.datas(limit: 200));
    if (datas == null || !mounted) return;
    if (datas.items.isEmpty) return toast(context, 'No Data Points to Backup', error: true);
    final map = {for (final d in datas.items) d.name: d};
    final f = await formDialog(context, 'Backup', [
      FieldSpec('data', 'Data Point', kind: 'choice', options: map.keys.toList()),
      const FieldSpec('path', 'Starting Folder', kind: 'path', initial: '/', required: true),
      const FieldSpec('tags', 'Tags (comma Separated)'),
      const FieldSpec('globs', 'Include Globs (comma/newline Separated)', kind: 'multiline'),
      const FieldSpec('ignore', 'Ignore Globs', kind: 'multiline'),
      const FieldSpec('max', 'Max File Size (Optional)', kind: 'capacity'),
      const FieldSpec('dry', 'Dry Run', kind: 'bool'),
    ], ok: 'Start', pick: (v) async {
      final r = await pickFolder(context, initialPointId: map[v['data']]?.id, initialPath: v['path'], title: 'Choose Folder to Backup');
      return r?.path;
    });
    if (f == null) return;
    final max = int.tryParse(f['max'] ?? '');
    final j = await guarded(context, () => _v.backup(widget.repoId, {
          'dataId': map[f['data']]!.id, 'path': f['path'], 'tags': splitList(f['tags']!), 'globs': splitList(f['globs']!),
          'ignoreGlobs': splitList(f['ignore']!), 'maxFileSize': max, 'dryRun': f['dry'] == 'true'}));
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
    final f = await formDialog(context, 'View Retention', [
      const FieldSpec('last', 'Keep Last N', number: true),
      const FieldSpec('hourly', 'Keep Hourly', number: true),
      const FieldSpec('daily', 'Keep Daily', number: true),
      const FieldSpec('weekly', 'Keep Weekly', number: true),
      const FieldSpec('monthly', 'Keep Monthly', number: true),
      const FieldSpec('yearly', 'Keep Yearly', number: true),
      const FieldSpec('within', 'Keep Within Days', number: true),
      const FieldSpec('reservePct', 'Keep Free Space (%)', number: true),
      const FieldSpec('dry', 'Dry Run (preview in Log)', kind: 'bool', initial: 'true'),
    ], ok: 'Run', intro: 'Locked snapshots and the newest snapshot of each data point are never deleted. At least one rule is required.');
    if (f == null) return;
    int n(String k) => int.tryParse(f[k] ?? '') ?? 0;
    final policy = {
      'keepLast': n('last'), 'keepHourly': n('hourly'), 'keepDaily': n('daily'), 'keepWeekly': n('weekly'),
      'keepMonthly': n('monthly'), 'keepYearly': n('yearly'), 'keepWithinDays': n('within'), 'reservePercent': n('reservePct'),
    };
    if (policy.values.every((v) => v == 0)) return toast(context, 'Set at Least One Rule', error: true);
    final j = await guarded(context, () => _v.retention(widget.repoId, policy, dryRun: f['dry'] == 'true'));
    if (j != null) _queued(j);
  }

  Future<void> _password() async {
    final f = await formDialog(context, 'Change Stored Password', [
      const FieldSpec('cur', 'Current Password', kind: 'secret', required: true),
      const FieldSpec('new', 'New Password (min 8)', kind: 'secret', required: true),
    ], intro: 'This only changes the password the system uses to open the repository. It does not re-encrypt it — use it to correct a wrong password.');
    if (f == null) return;
    await guarded(context, () => _v.changeRepoPassword(widget.repoId, f['cur']!, f['new']!));
    if (mounted) toast(context, 'Password Updated');
  }

  Widget _header() {
    final r = _repo;
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (r != null) ...[
                Row(children: [
                  Expanded(child: UsageBar(used: r.usedBytes, max: r.maxBytes)),
                  const SizedBox(width: 12),
                  Text('${fmtBytes(r.usedBytes)} of ${fmtBytes(r.maxBytes)}', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(width: 8),
                  chip(context, r.healthLabel, color: r.isError ? cs.errorContainer : null),
                ]),
                if (r.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.error!, style: TextStyle(color: cs.error, fontSize: 12))),
                const SizedBox(height: 12),
              ],
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: _repo == null ? null : () => _browse(), icon: const Icon(Icons.folder_open), label: const Text('Browse Latest')),
                FilledButton.tonalIcon(onPressed: _backup, icon: const Icon(Icons.backup_outlined), label: const Text('Backup Now')),
                OutlinedButton.icon(
                  onPressed: () async {
                    final j = await guarded(context, () => _v.check(widget.repoId));
                    if (j != null) _queued(j);
                  },
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Start Check'),
                ),
                OutlinedButton.icon(onPressed: _retention, icon: const Icon(Icons.auto_delete_outlined), label: const Text('View Retention')),
              ]),
            ]),
          ),
        ),
      ),
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
                      if (r != null && mounted) toast(context, '${toStr(r['message']) ?? 'Done'} (snapshot id changed)');
                      _key.currentState?.refresh();
                    case 'copy':
                      copyText(context, s.id, 'Snapshot id copied');
                    case 'forget':
                      if (await confirm(context, 'Delete Snapshot?', 'Locked snapshots are refused. Space is only freed by a retention run.', ok: 'Delete', danger: true)) {
                        final j = await guarded(context, () => _v.forget(widget.repoId, [s.id]));
                        if (j != null) _queued(j);
                      }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'restore', child: Text('Restore…')),
                  PopupMenuItem(value: 'lock', child: Text(s.locked ? 'Unlock' : 'Lock')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy Id')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_repo?.name ?? 'Repository'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (a) {
              if (a == 'pw') _password();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'pw', child: Text('Change Stored password…'))],
          ),
        ],
        bottom: TabBar(controller: _tc, tabs: const [Tab(text: 'Snapshots'), Tab(text: 'Jobs'), Tab(text: 'Schedules')]),
      ),
      floatingActionButton: _tc.index == 0 ? FloatingActionButton.extended(onPressed: _backup, icon: const Icon(Icons.backup), label: const Text('Backup')) : null,
      body: Column(children: [
        _header(),
        Expanded(
          child: TabBarView(controller: _tc, children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: CursorList<Snapshot>(
                  key: _key,
                  empty: 'No snapshots yet — run a backup',
                  emptyIcon: Icons.camera_alt_outlined,
                  autoRefresh: const Duration(seconds: 5),
                  fetch: (c) => _v.snapshots(widget.repoId, cursor: c),
                  itemBuilder: (ctx, s, i) => _snapshotCard(s),
                ),
              ),
            ),
            JobsList(repoId: widget.repoId),
            SchedulesList(repoId: widget.repoId),
          ]),
        ),
      ]),
    );
  }
}
