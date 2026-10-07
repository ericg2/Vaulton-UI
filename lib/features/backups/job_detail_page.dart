import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import 'job_text.dart';
import 'job_widgets.dart';
import 'log_widgets.dart';
import 'repo_page.dart';
import 'snapshot_browser.dart';

/// Two tabs: an overview (status, progress, stages, details, options) and a live log.
class JobDetailPage extends ConsumerStatefulWidget {
  /// [showVaultLink]: null (default) hides "Open Backup Vault" automatically when that
  /// vault's page is already open, which avoids vault -> job -> vault loops.
  const JobDetailPage({super.key, required this.jobId, this.admin = false, this.showVaultLink, this.initialTab = 0});
  final String jobId;
  final bool admin;
  final bool? showVaultLink;
  final int initialTab;
  @override
  ConsumerState<JobDetailPage> createState() => _JobDetailPageState();
}

class _JobDetailPageState extends ConsumerState<JobDetailPage> {
  RepoJob? _job;
  Object? _error;
  Timer? _timer;
  bool _busy = false;
  String? _repoName, _dataName;
  Json? _backupSummary;
  String? _loadedContextJobId;

  // log state, newest first
  final List<JobMessage> _log = [];
  final Set<String> _ids = {};
  String? _olderCursor;
  bool _hasOlder = false, _loadingOlder = false;
  String _search = '';
  String? _priorityFilter;
  final _searchCtl = TextEditingController();

  Vaulton get _v => ref.read(vaultonProvider);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_job == null || _job!.active) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final j = await _v.job(widget.jobId, admin: widget.admin);
      if (!mounted) return;
      setState(() {
        _job = j;
        _error = null;
      });
      if (_loadedContextJobId != j.id) {
        _loadedContextJobId = j.id;
        await _loadContext(j);
      }
      await _refreshLog(j);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadContext(RepoJob j) async {
    try {
      final results = await Future.wait([
        _v.repo(j.repoId),
        if (j.dataId != null) _v.datas(search: j.dataId, limit: 100),
        if (j.kind == 'backup' && j.snapshotId != null && j.snapshotId!.isNotEmpty)
          _v.snapshots(j.repoId, idPrefix: j.snapshotId, limit: 2),
      ]);
      if (!mounted) return;
      final repo = results[0] as Point;
      Point? data;
      var resultIndex = 1;
      if (j.dataId != null) {
        final pg = results[resultIndex++] as Paged<Point>;
        data = pg.items.where((p) => p.id == j.dataId).firstOrNull;
      }
      Json? summary;
      if (j.kind == 'backup' && j.snapshotId != null && j.snapshotId!.isNotEmpty && resultIndex < results.length) {
        final pg = results[resultIndex] as Paged<Snapshot>;
        final snap = pg.items.where((s) => s.id == j.snapshotId || s.id.startsWith(j.snapshotId!)).firstOrNull;
        summary = snap?.summary;
      }
      setState(() {
        _repoName = repo.name;
        _dataName = data?.name;
        _backupSummary = summary;
      });
    } catch (_) {
      // Names are supplementary; the IDs remain available if lookup fails.
    }
  }

  Future<void> _refreshLog(RepoJob j) async {
    if (widget.admin) {
      // Admins viewing someone else's job only get the embedded recent lines.
      final m = [...j.messages]..sort((a, b) => (b.time ?? DateTime(1970)).compareTo(a.time ?? DateTime(1970)));
      if (mounted) {
        setState(() {
          _log
            ..clear()
            ..addAll(m);
          _hasOlder = false;
        });
      }
      return;
    }
    try {
      final pg = await _v.jobMessages(j.id, search: _search, limit: 200, order: 'Desc');
      if (!mounted) return;
      final fresh = pg.items.where((m) => !_ids.contains(m.id)).toList();
      setState(() {
        if (_log.isEmpty) {
          _olderCursor = pg.nextCursor;
          _hasOlder = pg.hasMore;
        }
        _ids.addAll(fresh.map((m) => m.id));
        _log.insertAll(0, fresh);
      });
    } catch (_) {
      // Fall back to the lines embedded in the job so the tab is never empty.
      if (mounted && _log.isEmpty && j.messages.isNotEmpty) {
        setState(() => _log.addAll([...j.messages].reversed));
      }
    }
  }

  Future<void> _loadOlder() async {
    if (!_hasOlder || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      final pg = await _v.jobMessages(widget.jobId, search: _search, cursor: _olderCursor, limit: 200, order: 'Desc');
      if (!mounted) return;
      setState(() {
        final older = pg.items.where((m) => _ids.add(m.id)).toList();
        _log.addAll(older);
        _olderCursor = pg.nextCursor;
        _hasOlder = pg.hasMore;
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _applySearch(String q) {
    setState(() {
      _search = q.trim();
      _log.clear();
      _ids.clear();
      _olderCursor = null;
      _hasOlder = false;
    });
    if (_job != null) _refreshLog(_job!);
  }

  List<JobMessage> get _visible => _log.where((m) => logPriorityMatches(m.priority, _priorityFilter)).toList();

  // ----------------------------------------------------------------- actions
  Future<void> _cancel(RepoJob j) async {
    if (!await confirm(context, 'Cancel this job?', 'A running job is told to stop and finishes shortly after.', ok: 'Cancel Job', danger: true)) return;
    await guarded(context, () => _v.cancelJob(j.id, admin: widget.admin));
    _refresh();
  }

  Future<void> _openRepo(RepoJob j) async {
    final repo = await guarded(context, () => _v.repo(j.repoId));
    if (repo != null && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => RepoPage(repoId: repo.id, repo: repo)));
  }

  Future<void> _browse(RepoJob j) async {
    final repo = await guarded(context, () => _v.repo(j.repoId));
    if (repo != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: repo, snapshotId: j.snapshotId)));
    }
  }

  // ------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final j = _job;
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab < 0 ? 0 : (widget.initialTab > 1 ? 1 : widget.initialTab),
      child: Scaffold(
        appBar: AppBar(
          title: Text(j == null ? 'Job' : kindLabel(j.kind)),
          actions: [
            if (j != null && j.active) IconButton(tooltip: 'Cancel Job', icon: const Icon(Icons.stop_circle_outlined), onPressed: () => _cancel(j)),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
          ],
          bottom: TabBar(tabs: [const Tab(text: 'Overview'), Tab(text: _log.isEmpty ? 'Log' : 'Log (${_log.length}${_hasOlder ? '+' : ''})')]),
        ),
        body: j == null
            ? (_error != null ? ErrorView(_error!, onRetry: _refresh) : const Center(child: CircularProgressIndicator()))
            : TabBarView(children: [_overview(j), _logTab(j)]),
      ),
    );
  }

  Widget _centered(Widget child, {double width = 900}) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));

  // ---------------------------------------------------------------- overview
  Widget _overview(RepoJob j) {
    return _centered(ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      _hero(j),
      if (j.stages.isNotEmpty) _stagesCard(j),
      _detailsCard(j),
      _backupSummaryCard(j),
      _optionsCard(j),
    ]));
  }

  Widget _hero(RepoJob j) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = phaseStyle(context, j.phase);
    final summary = jobSummary(j);
    final err = cleanJobError(j.error);
    final showVault = widget.showVaultLink ?? !RepoPage.isOpen(j.repoId);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: st.bg, shape: BoxShape.circle),
              child: Icon(kindIcon(j.kind), color: st.fg, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(kindLabel(j.kind), style: t.titleLarge),
                if (summary.isNotEmpty) Text(summary, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 8),
            StatusPill(j.phase),
          ]),
          if (j.active) ...[
            const SizedBox(height: 20),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: j.phase == JobPhase.waiting ? null : j.liveFraction, minHeight: 8)),
            const SizedBox(height: 6),
            Text(
              j.phase == JobPhase.waiting
                  ? (j.scheduleDate != null && j.scheduleDate!.isAfter(DateTime.now()) ? 'Starts ${fmtDate(j.scheduleDate)}' : 'Waiting for a free slot…')
                  : j.liveTotal > 0
                      ? '${fmtBytes(j.liveDone)} of ${fmtBytes(j.liveTotal)}  ·  ${((j.liveFraction ?? 0) * 100).toStringAsFixed(0)}%'
                      : 'Working…',
              style: t.bodySmall,
            ),
          ],
          if (err.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.error_outline, color: cs.onErrorContainer),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(err, style: TextStyle(color: cs.onErrorContainer))),
                IconButton(visualDensity: VisualDensity.compact, tooltip: 'Copy', icon: Icon(Icons.copy, size: 18, color: cs.onErrorContainer), onPressed: () => copyText(context, err)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (j.kind == 'backup' && j.phase == JobPhase.succeeded && j.snapshotId != null && j.options['dryRun'] != true)
              FilledButton.icon(onPressed: () => _browse(j), icon: const Icon(Icons.folder_open), label: const Text('Browse Snapshot')),
            if (showVault) OutlinedButton.icon(onPressed: () => _openRepo(j), icon: const Icon(Icons.inventory_2_outlined), label: const Text('Open Backup Vault')),
            if (j.active) OutlinedButton.icon(onPressed: () => _cancel(j), icon: const Icon(Icons.stop_circle_outlined), label: const Text('Cancel')),
          ]),
        ]),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  Widget _kv(String k, Widget v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline))),
          Expanded(child: v),
        ]),
      );

  Widget _stagesCard(RepoJob j) => _card('Progress', [
        for (final s in j.stages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s.title)),
                if (s.finished)
                  Icon(Icons.check_circle, size: 18, color: Theme.of(context).colorScheme.primary)
                else if (s.fraction != null)
                  Text('${(s.fraction! * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelMedium),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: s.finished ? 1 : (j.active ? s.fraction : s.fraction ?? 0), minHeight: 6)),
            ]),
          ),
      ]);

  Widget _detailsCard(RepoJob j) {
    Widget copyable(String v) => Row(children: [
          Expanded(child: SelectableText(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Copy', icon: const Icon(Icons.copy, size: 16), onPressed: () => copyText(context, v)),
        ]);
    Widget namedId(String? name, String id) {
      final cs = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name != null && name.isNotEmpty) Text(name, style: Theme.of(context).textTheme.bodyMedium),
          Row(children: [
            Expanded(
              child: SelectableText(
                id,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Copy',
              icon: Icon(Icons.copy, size: 16, color: cs.onSurfaceVariant),
              onPressed: () => copyText(context, id),
            ),
          ]),
        ],
      );
    }
    return _card('Details', [
      _kv('Job ID', copyable(j.id)),
      _kv('Job Type', Text(kindLabel(j.kind))),
      _kv('Status', Text(phaseStyle(context, j.phase).label)),
      _kv('Backup Vault', namedId(_repoName, j.repoId)),
      if (j.dataId != null) _kv('Data Point', namedId(_dataName, j.dataId!)),
      if (j.scheduleId != null) _kv('Schedule', copyable(j.scheduleId!)),
      if (j.snapshotId != null) _kv('Snapshot ID', copyable(j.snapshotId!)),
      if (j.options['dryRun'] == true) _kv('Run Type', const Text('Test Run')),
            _kv('Created', Text(fmtDate(j.createdAt))),
      if (j.scheduleDate != null) _kv('Not Before', Text(fmtDate(j.scheduleDate))),
      if (j.startDate != null) _kv('Started', Text(fmtDate(j.startDate))),
      if (j.endDate != null) _kv('Finished', Text(fmtDate(j.endDate))),
      if (j.duration != null) _kv('Duration', Text(fmtDuration(j.duration!))),
    ]);
  }

  Widget _backupSummaryCard(RepoJob j) {
    final summary = _backupSummary;
    if (j.kind != 'backup' || summary == null || summary.isEmpty) return const SizedBox.shrink();

    String value(String key, dynamic v) {
      if (v is bool) return v ? 'Yes' : 'No';
      if (v is num && key.toLowerCase().contains('bytes')) return fmtBytes(v.toInt());
      if (v is List) return v.join(', ');
      if (v is Map) return v.entries.map((e) => '${pretty('${e.key}')}: ${e.value}').join('\n');
      return '$v';
    }

    return _card('Backup Summary', [
      for (final e in summary.entries)
        if (e.value != null && e.value != '')
          _kv(pretty(e.key), SelectableText(value(e.key, e.value))),
    ]);
  }

  Widget _optionsCard(RepoJob j) {
    final rows = <Widget>[];
    for (final e in j.options.entries) {
      if (e.key == 'mode') continue;
      final v = e.value;
      Widget? w;
      if (v == null || v == false || v == '' || (v is List && v.isEmpty) || (v is Map && v.isEmpty)) continue;
      if (v is List) {
        w = Wrap(children: [for (final x in v) chip(context, '$x')]);
      } else if (v is Map) {
        final parts = v.entries.where((x) => x.value != null && x.value != 0 && x.value != false).map((x) => '${pretty('${x.key}')}: ${x.value}');
        if (parts.isEmpty) continue;
        w = SelectableText(parts.join('\n'));
      } else if (v == true) {
        w = const Text('Yes');
      } else {
        w = SelectableText('$v');
      }
      rows.add(_kv(pretty(e.key), w));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card('Options', rows);
  }

  // --------------------------------------------------------------------- log
  Widget _logTab(RepoJob j) {
    final lines = _visible;
    return _centered(
      Column(children: [
        LogFilterBar(
          searchController: _searchCtl,
          search: _search,
          priority: _priorityFilter,
          onSearch: _applySearch,
          onPriority: (p) => setState(() => _priorityFilter = p),
          onCopy: lines.isEmpty ? null : () => copyText(context, lines.reversed.map(_fmtLine).join('\n'), 'Log copied'),
          copyEnabled: lines.isNotEmpty,
        ),
        const Divider(height: 1),
        Expanded(
          child: lines.isEmpty && !_hasOlder
              ? EmptyView(_log.isEmpty ? (j.active ? 'Waiting for log output…' : 'No messages') : 'No lines match this filter', icon: Icons.notes)
              : SelectionArea(
                  child: ListView.builder(
                    reverse: true, // newest line at the bottom, scroll up for history
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: lines.length + (_hasOlder ? 1 : 0),
                    itemBuilder: (c, i) {
                      if (i == lines.length) {
                        return Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: _loadingOlder
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton.icon(onPressed: _loadOlder, icon: const Icon(Icons.expand_less), label: const Text('Load Older Lines')),
                          ),
                        );
                      }
                      return _logLine(lines[i]);
                    },
                  ),
                ),
        ),
      ]),
      width: 1100,
    );
  }

  static final _hms = DateFormat.Hms();
  String _fmtLine(JobMessage m) => '${m.time == null ? '--:--:--' : _hms.format(m.time!)} [${m.priority}] ${m.message}';

  Widget _logLine(JobMessage m) => LogLine(time: m.time, priority: m.priority, message: m.message);}
