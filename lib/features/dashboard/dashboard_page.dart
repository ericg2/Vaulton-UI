import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/api_client.dart';
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
  bool _busy = false, _wasVisible = true, _dirty = false;

  bool get _canJobs => ref.read(userProvider)?.has(Scopes.jobsManage) ?? false;
  bool get _canPower => ref.read(userProvider)?.has(Scopes.serverPower) ?? false;

  Future<void> _requestPowerAction(String action, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label Server?'),
        content: Text('This will $action the Vaulton host. You will lose access until it is powered back on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(label)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(vaultonProvider).requestPowerAction(action);
      if (mounted) toast(context, '$label request was accepted by the host agent. Check Administration → Configuration for the execution result.');
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The dashboard sits under other pages (Files, Jobs...) and in a tab stack.
    // When it becomes visible again, reload right away so usage is never stale
    // after an upload, delete or backup done elsewhere.
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_wasVisible) _load();
    _wasVisible = visible;
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) {
      _dirty = true; // something changed mid-request: reload once more when it finishes
      return;
    }
    _busy = true;
    _dirty = false;
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
      if (_dirty && mounted) {
        _dirty = false;
        _load();
      }
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
    final greet = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');

    Widget body;
    if (_error != null && d == null) {
      body = KeyedSubtree(key: const ValueKey('err'), child: ErrorView(_error!, onRetry: _load));
    } else if (d == null) {
      body = const Center(key: ValueKey('load'), child: CircularProgressIndicator());
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
        _Stat(Icons.folder_outlined, '${d.datas.length}', d.datas.length == 1 ? 'Data Folder' : 'Data Folders', () => widget.onNavigate?.call('Data Folders')),
        _Stat(Icons.inventory_2_outlined, '${d.repos.length}', d.repos.length == 1 ? 'Backup Vault' : 'Backup Vaults', () => widget.onNavigate?.call('Backup Vaults')),
        if (_canJobs) _Stat(Icons.sync, '${running.length + waiting}', 'Active Jobs', () => widget.onNavigate?.call('Activity'), highlight: running.isNotEmpty),
        if (_canJobs) _Stat(failed > 0 ? Icons.error_outline : Icons.check_circle_outline, '$failed', 'Failed (24h)', () => widget.onNavigate?.call('Activity'), bad: failed > 0),
      ];

      body = RefreshIndicator(
        key: const ValueKey('data'),
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
          children: [
            if (MediaQuery.sizeOf(context).width < 800)
              FadeSlideIn(key: const ValueKey('badge'), child: const Card(margin: EdgeInsets.fromLTRB(16, 4, 16, 4), child: ServerBadge(inline: true))),
            FadeSlideIn(
              key: const ValueKey('greet'),
              delay: const Duration(milliseconds: 60),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$greet, ${u.displayName}', style: t.titleLarge),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Row(key: ValueKey(failedPoints > 0 || failed > 0), children: [
                    Icon((failedPoints > 0 || failed > 0) ? Icons.warning_amber_rounded : Icons.check_circle_outline, size: 16, color: (failedPoints > 0 || failed > 0) ? cs.error : cs.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        failedPoints > 0
                            ? '$failedPoints storage item${failedPoints == 1 ? ' needs' : 's need'} attention'
                            : (failed > 0 ? '$failed job${failed == 1 ? '' : 's'} failed in the last 24 hours' : 'Everything looks healthy'),
                        style: t.bodyMedium?.copyWith(color: (failedPoints > 0 || failed > 0) ? cs.error : cs.onSurfaceVariant),
                      ),
                    ),
                  ]),
                ),
              ]),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(key: const ValueKey('stats'), builder: (ctx, c) {
                final cols = c.maxWidth > 700 ? stats.length : 2;
                final w = (c.maxWidth - 10 * (cols - 1)) / cols;
                return Wrap(spacing: 10, runSpacing: 10, children: [
                  for (var i = 0; i < stats.length; i++)
                    FadeSlideIn(key: ValueKey('stat$i'), delay: Duration(milliseconds: 120 + 70 * i), child: SizedBox(width: w, child: stats[i])),
                ]);
              }),
            ),
            const SizedBox(height: 4),
            if (d.datas.isEmpty)
              FadeSlideIn(
                key: const ValueKey('firstrun'),
                delay: const Duration(milliseconds: 300),
                child: Card(
                  color: cs.tertiaryContainer,
                  child: ListTile(
                    leading: Icon(Icons.rocket_launch_outlined, color: cs.onTertiaryContainer),
                    title: Text('Get Started', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
                    subtitle: Text('Create a data folder in Storage to start storing files.', style: TextStyle(color: cs.onTertiaryContainer)),
                    trailing: Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
                    onTap: () => widget.onNavigate?.call('Data Folders'),
                  ),
                ),
              ),
            if (_canPower)
              Section('Server Power', children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () => _requestPowerAction('sleep', 'Sleep'),
                      icon: const Icon(Icons.bedtime_outlined),
                      label: const Text('Sleep'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _requestPowerAction('hibernate', 'Hibernate'),
                      icon: const Icon(Icons.nights_stay_outlined),
                      label: const Text('Hibernate'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _requestPowerAction('shutdown', 'Shut Down'),
                      icon: const Icon(Icons.power_settings_new_rounded),
                      label: const Text('Shut Down'),
                    ),
                  ]),
                ),
              ]),
            Section('Quick Actions', children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_canJobs) FilledButton.icon(onPressed: () => startBackup(context, ref), icon: const Icon(Icons.backup_outlined), label: const Text('Backup Now')),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesPage()));
                      if (mounted) _load(); // usage may have changed while you were in Files
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload'),
                  ),
                  OutlinedButton.icon(onPressed: () => widget.onNavigate?.call('Storage'), icon: const Icon(Icons.storage_outlined), label: const Text('Storage')),
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
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        UsageBar(used: used, max: cap),
                        const SizedBox(height: 8),
                        Text('${fmtBytes(used)} used of ${fmtBytes(cap)} allocated', style: t.bodySmall),
                        if (lastOk != null) ...[
                          const SizedBox(height: 4),
                          Text('Last backup: ${fmtDate(lastOk.endDate ?? lastOk.startDate)}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ]),
            if (_canJobs) ...[
              Section('Running Now', children: [
                if (running.isEmpty && waiting == 0)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text('No jobs running.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
                else
                  for (final j in d.jobs.where((j) => j.active))
                    JobCard(job: j, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)))),
              ]),
              Section('Activity', children: [
                if (d.jobs.where((j) => !j.active).isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text('No finished jobs yet.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
                else
                  for (final j in d.jobs.where((j) => !j.active).take(5))
                    JobCard(job: j, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id)))),
                if (d.jobs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: () => widget.onNavigate?.call('Activity'), child: const Text('View All')),
                    ),
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
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: AnimatedSwitcher(duration: const Duration(milliseconds: 160), child: body),
        ),
      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, color: fg, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Numbers count up when they first appear and whenever they change.
                Builder(builder: (_) {
                  final n = int.tryParse(value);
                  final style = Theme.of(context).textTheme.titleLarge?.copyWith(color: fg, height: 1.1);
                  if (n == null) return Text(value, style: style);
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: n.toDouble()),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => Text('${v.round()}', style: style),
                  );
                }),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
