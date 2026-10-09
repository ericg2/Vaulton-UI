import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import 'job_detail_page.dart';
import '../../core/timezones.dart';
import '../files/folder_picker.dart';
import 'backup_flow.dart';
import 'backup_options.dart';
import 'job_text.dart';
import 'job_widgets.dart';
import 'repo_page.dart';

class BackupsPage extends ConsumerWidget {
  const BackupsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('Activity'), bottom: const TabBar(tabs: [Tab(text: 'Jobs'), Tab(text: 'Schedules')])),
          floatingActionButton: Builder(
            builder: (ctx) => AnimatedBuilder(
              animation: DefaultTabController.of(ctx),
              builder: (_, _) => DefaultTabController.of(ctx).index == 0
                  ? FloatingActionButton.extended(onPressed: () => startBackup(ctx, ref), icon: const Icon(Icons.backup), label: const Text('Backup'))
                  : const SizedBox.shrink(),
            ),
          ),
          body: const TabBarView(children: [JobsList(), SchedulesList()]),
        ),
      );
}

const _statusFilters = <(String label, String? value)>[
  ('All', null),
  ('Running', 'Running'),
  ('Waiting', 'Pending'),
  ('Succeeded', 'Succeeded'),
  ('Failed', 'Failed'),
  ('Cancelled', 'Cancelled'),
];

/// Job history with status filter chips and live refresh while anything is running.
class JobsList extends ConsumerStatefulWidget {
  const JobsList({
    super.key,
    this.repoId,
    this.dataId,
    this.admin = false,
    this.showFilters = true,
    this.externalStatus,
  });
  final String? repoId, dataId;
  final bool admin;
  final bool showFilters;
  final String? externalStatus;
  @override
  ConsumerState<JobsList> createState() => _JobsListState();
}

class _JobsListState extends ConsumerState<JobsList> {
  final _key = GlobalKey<CursorListState<RepoJob>>();
  Timer? _t;
  bool _anyActive = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    // Fast while something is running, slow otherwise so new jobs still appear on their own.
    var tick = 0;
    _t = Timer.periodic(const Duration(seconds: 3), (_) {
      tick++;
      // Silent: updates rows in place instead of clearing the list and showing a spinner.
      if (mounted && TickerMode.valuesOf(context).enabled && (_anyActive || tick % 5 == 0)) _key.currentState?.silentRefresh();
    });
  }

  @override
  void didUpdateWidget(covariant JobsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalStatus != widget.externalStatus && widget.externalStatus != _status) {
      _status = widget.externalStatus;
      WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.refresh());
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _setStatus(String? s) {
    setState(() => _status = s);
    WidgetsBinding.instance.addPostFrameCallback((_) => _key.currentState?.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.read(vaultonProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(children: [
          if (widget.showFilters)
            SizedBox(
              height: 48,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), children: [
                for (final f in _statusFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(label: Text(f.$1), selected: _status == f.$2, onSelected: (_) => _setStatus(f.$2)),
                  ),
              ]),
            ),
          Expanded(
            child: CursorList<RepoJob>(
              key: _key,
              empty: _status == null ? 'No jobs yet' : 'No ${_status!.toLowerCase()} jobs',
              emptyIcon: Icons.work_history_outlined,
              onChanged: (l) => _anyActive = l.any((j) => j.active),
              fetch: (c) => v.jobs(cursor: c, repoId: widget.repoId, dataId: widget.dataId, admin: widget.admin, status: widget.externalStatus ?? _status),
              itemBuilder: (ctx, j, i) => JobCard(
                job: j,
                onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id, admin: widget.admin)))
                    .then((_) => _key.currentState?.refresh()),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.job, required this.onTap});
  final RepoJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(pointNamesProvider).value ?? const <String, String>{};
    final repoName = names[job.repoId];
    final dataName = job.dataId == null ? null : names[job.dataId!];
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = phaseStyle(context, job.phase);
    final summary = jobSummary(job);
    final when = job.startDate ?? job.scheduleDate ?? job.createdAt;
    final dur = job.duration;
    final meta = [
      if (job.phase == JobPhase.waiting && job.scheduleDate != null) 'Starts ${fmtDate(job.scheduleDate)}' else fmtDate(when),
      if (dur != null) fmtDuration(dur),
      if (job.scheduleId != null) 'Scheduled',
    ].join('  ·  ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: st.bg, shape: BoxShape.circle),
              child: Icon(kindIcon(job.kind), color: st.fg),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(kindLabel(job.kind), style: t.titleMedium)),
                  StatusPill(job.phase),
                ]),
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                if (repoName != null || dataName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      if (dataName != null) _tag(context, Icons.folder_outlined, dataName),
                      if (dataName != null && repoName != null) Icon(Icons.arrow_forward, size: 14, color: cs.outline),
                      if (repoName != null) _tag(context, Icons.inventory_2_outlined, repoName),
                    ]),
                  ),
                const SizedBox(height: 4),
                Text(meta, style: t.bodySmall?.copyWith(color: cs.outline)),
                if (job.phase == JobPhase.running) ...[
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: job.progressFraction, minHeight: 6)),
                  if (job.progressTotal > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${job.currentStage?.title == 'Working' ? kindLabel(job.kind) : (job.currentStage?.title ?? kindLabel(job.kind))} · ${fmtBytes(job.progressDone)} of ${fmtBytes(job.progressTotal)}',
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                ],
                if (cleanJobError(job.error).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(cleanJobError(job.error), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.error)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _tag(BuildContext c, IconData icon, String text) {
  final cs = Theme.of(c).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: Theme.of(c).textTheme.labelMedium)),
    ]),
  );
}

// ============================================================== SCHEDULES
class SchedulesList extends ConsumerStatefulWidget {
  const SchedulesList({super.key, this.repoId, this.header});
  final String? repoId;
  final Widget? header;
  @override
  ConsumerState<SchedulesList> createState() => _SchedulesListState();
}

class _SchedulesListState extends ConsumerState<SchedulesList> {
  final _key = GlobalKey<CursorListState<Schedule>>();
  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _edit([Schedule? s, String? startMode, String? startRepoId]) async {
    final repos = await guarded(context, () => _v.repos(limit: 200));
    final datas = await guarded(context, () => _v.datas(limit: 200));
    if (repos == null || datas == null || !mounted) return;
    if (repos.items.isEmpty) return toast(context, 'Create a backup vault first', error: true);
    String repoName(Point p) => p.name;
    final repoMap = {for (final r in repos.items) repoName(r): r};
    final dataMap = {for (final d in datas.items) d.name: d};
    final deviceTz = await deviceTimeZone();
    if (!mounted) return;
    final isNew = s == null;
    final curRepo = repos.items.where((r) => r.id == (s?.repoId ?? startRepoId ?? widget.repoId)).firstOrNull ?? repos.items.first;
    final curData = datas.items.where((d) => d.id == s?.dataId).firstOrNull;
    final f = await formDialog(context, isNew ? 'New Schedule' : 'Edit Schedule', [
      FieldSpec('name', 'Name', initial: s?.name ?? '', required: true),
      if (isNew) FieldSpec('repo', 'Backup Vault', kind: 'choice', options: repoMap.keys.toList(), initial: repoName(curRepo)),
      if (isNew) FieldSpec('mode', 'What to Run', kind: 'choice', options: ['Backup', 'Clean Up Snapshots', 'Health Check'], initial: startMode ?? 'Backup'),
      if ((s == null && startMode == null) || s?.mode == 'backup') ...[
        if (datas.items.isNotEmpty) FieldSpec('data', 'Back Up From', kind: 'choice', options: dataMap.keys.toList(), initial: curData?.name ?? dataMap.keys.first),
        FieldSpec('path', 'Folder to Back Up', kind: 'path', initial: '${s?.options['path'] ?? '/'}'),
      ],
      FieldSpec('cron', 'Schedule', kind: 'cron', initial: s?.cron ?? '0 2 * * *'),
      FieldSpec('tz', 'Time Zone', kind: 'choice', options: timeZoneOptions(device: deviceTz, extra: s?.timeZone), initial: s?.timeZone.isNotEmpty == true ? s!.timeZone : (deviceTz ?? 'UTC')),
      FieldSpec('enabled', 'Enabled', kind: 'bool', initial: '${s?.enabled ?? true}'),
      FieldSpec('skip', 'Skip if Already Running', kind: 'bool', initial: '${s?.skipIfRunning ?? true}'),
    ], ok: 'Save', pick: (v) async {
      final d = dataMap[v['data']];
      final r = await pickFolder(context, initialPointId: d?.id, initialPath: v['path'], title: 'Choose Folder to Backup');
      return r?.path;
    }, intro: 'Times follow the selected time zone.${isNew ? '\n\nTip: add a Clean Up Snapshots schedule so old snapshots don’t fill your vault.' : ''}');
    if (f == null || !mounted) return;
    try {
      final mode = s == null ? (f['mode'] == 'Backup' ? 'backup' : (f['mode'] == 'Clean Up Snapshots' ? 'retention' : 'check')) : s.mode;
      Map<String, dynamic>? policy;
      if (mode == 'retention') {
        final req = await showRetentionSheet(context, forSchedule: true, initial: s == null ? null : toJson(s.options['policy']));
        if (req == null || !mounted) return;
        policy = req.policy;
      }
      final Map<String, dynamic> opts = mode == 'backup'
          ? {'mode': 'backup', 'dataId': dataMap[f['data']]!.id, 'path': f['path']!.isEmpty ? '/' : f['path']}
          : (mode == 'retention' ? {'mode': 'retention', 'policy': policy, 'dryRun': false} : {'mode': 'check'});
      if (s == null) {
        await _v.createSchedule({
          'name': f['name'], 'repoId': repoMap[f['repo']]!.id, 'options': opts, 'cron': f['cron'], 'timeZone': f['tz'],
          'enabled': f['enabled'] == 'true', 'skipIfRunning': f['skip'] == 'true'});
      } else {
        await _v.patchSchedule(s.id, {
          'name': f['name'], 'options': opts, 'cron': f['cron'], 'timeZone': f['tz'],
          'enabled': f['enabled'] == 'true', 'skipIfRunning': f['skip'] == 'true'});
      }
      _key.currentState?.refresh();
      if (s == null && mode == 'backup') await _remindCleanup(repoMap[f['repo']]!.id);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// After a backup schedule is created, suggest a cleanup schedule if the vault has none.
  Future<void> _remindCleanup(String repoId) async {
    final existing = await _v.schedules(repoId: repoId, limit: 200);
    if (!mounted || existing.items.any((x) => x.mode == 'retention')) return;
    final go = await confirm(context, 'Add a Cleanup Schedule?',
        'Each backup adds a snapshot and nothing removes old ones. Without cleanup, this vault will eventually fill up and backups will fail.',
        ok: 'Set Up Cleanup Now');
    if (go && mounted) await _edit(null, 'Clean Up Snapshots', repoId);
  }

  Future<void> _preview(Schedule s) async {
    final times = await guarded(context, () => _v.previewCron(s.cron, tz: s.timeZone));
    if (times == null || !mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Next Runs'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [for (final t in times) Text(fmtDate(t))]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(pointNamesProvider).value ?? const <String, String>{};
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('New Schedule')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: CursorList<Schedule>(
            key: _key,
            header: widget.header,
            empty: 'No schedules yet',
            emptyIcon: Icons.schedule,
            autoRefresh: const Duration(seconds: 30),
            fetch: (c) => _v.schedules(cursor: c, repoId: widget.repoId),
            itemBuilder: (ctx, s, i) {
              final repoName = names[s.repoId] ?? 'Backup Vault';
              return Card(
                child: InkWell(
                  onTap: () => _edit(s),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(s.enabled ? Icons.schedule : Icons.pause_circle_outline),
                        title: Text(s.name),
                        subtitle: Text(
                          '${kindLabel(s.mode)} · ${s.cron} (${s.timeZone})\nNext: ${fmtDate(s.nextRunAt)} · Runs: ${s.runCount}',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (a) async {
                            switch (a) {
                              case 'run':
                                await guarded(context, () => _v.runSchedule(s.id));
                                ref.read(epochProvider.notifier).bump();
                                if (context.mounted) toast(context, 'Job queued');
                              case 'toggle':
                                await guarded(context, () => _v.patchSchedule(s.id, {'enabled': !s.enabled}));
                                _key.currentState?.refresh();
                              case 'preview':
                                _preview(s);
                              case 'del':
                                if (await confirm(context, 'Delete Schedule?', 'Existing jobs will not be affected.', ok: 'Delete', danger: true)) {
                                  await guarded(context, () => _v.deleteSchedule(s.id));
                                  _key.currentState?.refresh();
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'run', child: Text('Run Now')),
                            PopupMenuItem(value: 'toggle', child: Text(s.enabled ? 'Disable' : 'Enable')),
                            const PopupMenuItem(value: 'preview', child: Text('Preview Next Runs')),
                            const PopupMenuDivider(),
                            const PopupMenuItem(value: 'del', child: Text('Delete')),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              s.lastRunAt == null ? 'Last Run: Never' : 'Last Run: ${fmtDate(s.lastRunAt)}',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                            ),
                            chip(
                              ctx,
                              s.lastRunAt == null ? 'Never Run' : (s.lastError == null ? 'Succeeded' : 'Failed'),
                              color: s.lastRunAt == null ? null : (s.lastError == null ? Theme.of(ctx).colorScheme.primaryContainer : Theme.of(ctx).colorScheme.errorContainer),
                            ),
                            if (s.lastJobId != null)
                              TextButton.icon(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: s.lastJobId!, showVaultLink: widget.repoId == null))),
                                icon: const Icon(Icons.history, size: 18),
                                label: const Text('Last Run'),
                              ),
                          ],
                        ),
                      ),
                        if (widget.repoId == null)
                          TextButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RepoPage(repoId: s.repoId, initialTab: 2))),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: Text('Open $repoName'),
                          ),
                      ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
