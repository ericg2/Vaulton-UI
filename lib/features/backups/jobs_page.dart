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
import 'job_widgets.dart';

class BackupsPage extends ConsumerWidget {
  const BackupsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(title: const Text('Recent Jobs'), bottom: const TabBar(tabs: [Tab(text: 'Jobs'), Tab(text: 'Schedules')])),
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
  const JobsList({super.key, this.repoId, this.dataId, this.admin = false});
  final String? repoId, dataId;
  final bool admin;
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
      if (mounted && TickerMode.of(context) && (_anyActive || tick % 5 == 0)) _key.currentState?.silentRefresh();
    });
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
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
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
              empty: _status == null ? 'No Jobs Created' : 'No ${_status!.toLowerCase()} Jobs',
              emptyIcon: Icons.work_history_outlined,
              onChanged: (l) => _anyActive = l.any((j) => j.active),
              fetch: (c) => v.jobs(cursor: c, repoId: widget.repoId, dataId: widget.dataId, admin: widget.admin, status: _status),
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
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: job.liveFraction, minHeight: 6)),
                ],
                if (job.error != null && job.error!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(job.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.error)),
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
  const SchedulesList({super.key, this.repoId});
  final String? repoId;
  @override
  ConsumerState<SchedulesList> createState() => _SchedulesListState();
}

class _SchedulesListState extends ConsumerState<SchedulesList> {
  final _key = GlobalKey<CursorListState<Schedule>>();
  Vaulton get _v => ref.read(vaultonProvider);

  Future<void> _edit([Schedule? s]) async {
    final repos = await guarded(context, () => _v.repos(limit: 200));
    final datas = await guarded(context, () => _v.datas(limit: 200));
    if (repos == null || datas == null || !mounted) return;
    if (repos.items.isEmpty) return toast(context, 'Create a Repository First', error: true);
    String repoName(Point p) => p.name;
    final repoMap = {for (final r in repos.items) repoName(r): r};
    final dataMap = {for (final d in datas.items) d.name: d};
    final deviceTz = await deviceTimeZone();
    if (!mounted) return;
    final isNew = s == null;
    final curRepo = repos.items.where((r) => r.id == (s?.repoId ?? widget.repoId)).firstOrNull ?? repos.items.first;
    final curData = datas.items.where((d) => d.id == s?.dataId).firstOrNull;
    final f = await formDialog(context, isNew ? 'New Schedule' : 'Edit Schedule', [
      FieldSpec('name', 'Name', initial: s?.name ?? '', required: true),
      if (isNew) FieldSpec('repo', 'Repository', kind: 'choice', options: repoMap.keys.toList(), initial: repoName(curRepo)),
      if (s == null || s.mode == 'backup') ...[
        if (isNew) const FieldSpec('mode', 'Job Type', kind: 'choice', options: ['backup', 'check']),
        if (datas.items.isNotEmpty) FieldSpec('data', 'Data Source', kind: 'choice', options: dataMap.keys.toList(), initial: curData?.name ?? dataMap.keys.first),
        FieldSpec('path', 'Folder to Backup', kind: 'path', initial: '${s?.options['path'] ?? '/'}'),
      ],
      FieldSpec('cron', 'Schedule', kind: 'cron', initial: s?.cron ?? '0 2 * * *'),
      FieldSpec('tz', 'Time Zone', kind: 'choice', options: timeZoneOptions(device: deviceTz, extra: s?.timeZone), initial: s?.timeZone.isNotEmpty == true ? s!.timeZone : (deviceTz ?? 'UTC')),
      FieldSpec('enabled', 'Enabled', kind: 'bool', initial: '${s?.enabled ?? true}'),
      FieldSpec('skip', 'Skip Still Running', kind: 'bool', initial: '${s?.skipIfRunning ?? true}'),
    ], ok: 'Save', pick: (v) async {
      final d = dataMap[v['data']];
      final r = await pickFolder(context, initialPointId: d?.id, initialPath: v['path'], title: 'Choose Folder to Backup');
      return r?.path;
    }, intro: 'Please set the frequency. Uses the selected Time Zone.');
    if (f == null || !mounted) return;
    try {
      final mode = s == null ? f['mode'] : s.mode;
      final Map<String, dynamic> opts = mode == 'backup'
          ? {'mode': 'backup', 'dataId': dataMap[f['data']]!.id, 'path': f['path']!.isEmpty ? '/' : f['path']}
          : {'mode': 'check'};
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
    } catch (e) {
      if (mounted) toastError(context, e);
    }
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
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('New Schedule')),
      body: CursorList<Schedule>(
        key: _key,
        empty: 'No Schedules Created.',
        emptyIcon: Icons.schedule,
        autoRefresh: const Duration(seconds: 30),
        fetch: (c) => _v.schedules(cursor: c, repoId: widget.repoId),
        itemBuilder: (ctx, s, i) => Card(
          child: ListTile(
            leading: Icon(s.enabled ? Icons.schedule : Icons.pause_circle_outline),
            title: Text(s.name),
            subtitle: Text('${pretty(s.mode)} · ${s.cron} (${s.timeZone})\nNext: ${fmtDate(s.nextRunAt)} · Runs: ${s.runCount}${s.lastError != null ? '\n${s.lastError}' : ''}'),
            isThreeLine: true,
            onTap: () => _edit(s),
            trailing: PopupMenuButton<String>(
              onSelected: (a) async {
                switch (a) {
                  case 'run':
                    await guarded(context, () => _v.runSchedule(s.id));
                    ref.read(epochProvider.notifier).bump();
                    if (context.mounted) toast(context, 'Job Queued');
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
        ),
      ),
    );
  }
}

