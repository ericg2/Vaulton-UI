import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../backups/backup_flow.dart';
import '../backups/job_detail_page.dart';
import '../backups/jobs_page.dart' show JobCard;
import '../files/files_page.dart';
import '../shell/server_badge.dart';

class _Data {
  _Data(this.datas, this.repos, this.jobs);
  final List<Point> datas, repos;
  final List<RepoJob> jobs;
}

/// Landing screen: health, storage, running work, recent jobs and quick actions.
/// Reloads itself every few seconds and whenever something changes.
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key, this.onNavigate});

  /// Lets quick actions switch the shell to another section by label.
  final void Function(String label)? onNavigate;
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  _Data? _data;
  Object? _error;
  Timer? _t;
  bool _busy = false;

  bool get _canJobs => ref.read(userProvider)?.has(Scopes.jobsManage) ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && TickerMode.of(context)) _load();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    final v = ref.read(vaultonProvider);
    try {
      final r = await Future.wait([
        v.datas(limit: 200),
        v.repos(limit: 200),
        if (_canJobs) v.jobs(limit: 12) else Future.value(Paged<RepoJob>([], null, false)),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _Data((r[0] as Paged<Point>).items, (r[1] as Paged<Point>).items, (r[2] as Paged<RepoJob>).items);
        _error = null;
      });
    } catch (e) {
      if (mounted && _data == null) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(epochProvider, (_, _) => _load());
    final u = ref.watch(userProvider)!;
    final d = _data;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Good Morning' : (hour < 18 ? 'Good Afternoon' : 'Good Evening');

    Widget body;
    if (_error != null && d == null) {
      body = ErrorView(_error!, onRetry: _load);
    } else if (d == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final failedPoints = [...d.datas, ...d.repos].where((p) => p.isError).length;
      final running = d.jobs.where((j) => j.phase == JobPhase.running).toList();
      final waiting = d.jobs.where((j) => j.phase == JobPhase.waiting).length;
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final failed = d.jobs.where((j) => j.phase == JobPhase.failed && (j.endDate ?? j.createdAt ?? cutoff).isAfter(cutoff)).length;
      final lastOk = d.jobs.where((j) => j.kind == 'backup' && j.phase == JobPhase.succeeded).firstOrNull;
      final used = [...d.datas, ...d.repos].fold<int>(0, (a, p) => a + p.usedBytes);
      final cap = [...d.datas, ...d.repos].fold<int>(0, (a, p) => a + p.maxBytes);

      final stats = [
        _Stat(Icons.folder_outlined, '${d.datas.length}', 'Data Points', () => widget.onNavigate?.call('Storage')),
        _Stat(Icons.inventory_2_outlined, '${d.repos.length}', 'Repositories', () => widget.onNavigate?.call('Storage')),
        if (_canJobs) _Stat(Icons.sync, '${running.length + waiting}', 'Active Jobs', () => widget.onNavigate?.call('Recent Jobs'), highlight: running.isNotEmpty),
        if (_canJobs) _Stat(failed > 0 ? Icons.error_outline : Icons.check_circle_outline, '$failed', 'Failed (24h)', () => widget.onNavigate?.call('Recent Jobs'), bad: failed > 0),
      ];

      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (MediaQuery.sizeOf(context).width < 800)
              Card(margin: const EdgeInsets.only(bottom: 12), child: const Align(alignment: Alignment.centerLeft, child: ServerBadge())),
            Text('$greet, ${u.displayName}', style: t.headlineSmall),
            const SizedBox(height: 2),
            Text(
              failedPoints > 0
                  ? '$failedPoints storage point${failedPoints == 1 ? ' needs' : 's need'} attention'
                  : (failed > 0 ? '$failed job${failed == 1 ? '' : 's'} failed in the last 24 hours' : 'Everything looks healthy'),
              style: t.bodyMedium?.copyWith(color: (failedPoints > 0 || failed > 0) ? cs.error : cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 700 ? stats.length : 2;
              final w = (c.maxWidth - 12 * (cols - 1)) / cols;
              return Wrap(spacing: 12, runSpacing: 12, children: [for (final s in stats) SizedBox(width: w, child: s)]);
            }),
            const SizedBox(height: 16),
            Section('Quick Actions', children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_canJobs) FilledButton.icon(onPressed: () => startBackup(context, ref), icon: const Icon(Icons.backup), label: const Text('Backup Now')),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesPage())),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload Files'),
                  ),
                  OutlinedButton.icon(onPressed: () => widget.onNavigate?.call('Storage'), icon: const Icon(Icons.storage_outlined), label: const Text('Manage Storage')),
                ]),
              ),
            ]),
            if (cap > 0)
              Section('Storage Usage', children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        UsageBar(used: used, max: cap),
                        const SizedBox(height: 8),
                        Text('${fmtBytes(used)} used of ${fmtBytes(cap)} allocated', style: t.bodySmall),
                        if (lastOk != null) ...[
                          const SizedBox(height: 4),
                          Text('Last successful backup: ${fmtDate(lastOk.endDate ?? lastOk.startDate)}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
            if (_canJobs) ...[
              Section('Running Now', children: [
                if (running.isEmpty && waiting == 0)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('No jobs are running.'))
                else
                  for (final j in d.jobs.where((j) => j.active))
                    JobCard(job: j, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)))),
              ]),
              Section('Recent Jobs', children: [
                if (d.jobs.where((j) => !j.active).isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('No finished jobs yet.'))
                else
                  for (final j in d.jobs.where((j) => !j.active).take(5))
                    JobCard(job: j, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)))),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => widget.onNavigate?.call('Recent Jobs'), child: const Text('View All Jobs')),
                ),
              ]),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: body)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label, this.onTap, {this.highlight = false, this.bad = false});
  final IconData icon;
  final String value, label;
  final VoidCallback onTap;
  final bool highlight, bad;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = bad ? cs.errorContainer : (highlight ? cs.tertiaryContainer : cs.surfaceContainerHigh);
    final fg = bad ? cs.onErrorContainer : (highlight ? cs.onTertiaryContainer : cs.onSurface);
    return Card(
      margin: EdgeInsets.zero,
      color: bg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: fg, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: fg)),
                Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
