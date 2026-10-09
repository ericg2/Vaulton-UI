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
import 'vault_timeline.dart';

const double _kWideWidth = 840;
const double _kSidebarWidth = 400;
const double _kMaxWide = 1280;

/// One backup vault. Activity, snapshots, and automation each have a focused view.
class RepoPage extends ConsumerStatefulWidget {
  const RepoPage({super.key, required this.repoId, this.repo, this.initialTab = 0});
  final String repoId;
  final Point? repo;

  /// Tab order: 0 snapshots, 1 activity, 2 automation.
  final int initialTab;

  static final Map<String, int> _open = {};

  /// True while a page for this vault is on screen (used to hide "Open vault" links that would loop).
  static bool isOpen(String repoId) => (_open[repoId] ?? 0) > 0;
  @override
  ConsumerState<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends ConsumerState<RepoPage> with SingleTickerProviderStateMixin {
  final _cleanupKey = GlobalKey<CleanupCardState>();
  late final TabController _tc = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2));
  Point? _repo;
  Timer? _usageTimer;
  Vaulton get _v => ref.read(vaultonProvider);

  @override
  void initState() {
    super.initState();
    RepoPage._open[widget.repoId] = (RepoPage._open[widget.repoId] ?? 0) + 1;
    _repo = widget.repo;
    _tc.addListener(() {
      if (!_tc.indexIsChanging && mounted) _cleanupKey.currentState?.reload();
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
    RepoPage._open[widget.repoId] = (RepoPage._open[widget.repoId] ?? 1) - 1;
    _usageTimer?.cancel();
    _tc.dispose();
    super.dispose();
  }

  Future<void> _queued(RepoJob j) async {
    toast(context, '${kindLabel(j.kind)} queued');
    ref.read(epochProvider.notifier).bump();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id, showVaultLink: false)));
    if (mounted) ref.read(epochProvider.notifier).bump();
  }

  void _browseLatest() {
    final r = _repo;
    if (r == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: r)));
  }

  Future<int> _estimateSourceBytes(String pointId, String rootPath) async {
    var total = 0;
    final pending = <String>[rootPath.isEmpty ? '/' : rootPath];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      String? cursor;
      do {
        final page = await _v.list(pointId, dir, cursor: cursor, limit: 200);
        for (final node in page.items) {
          final path = node.pathIn(dir).replaceAll(RegExp(r'/+'), '/');
          if (!seen.add(path)) continue;
          if (node.isDir) {
            pending.add(path);
          } else if (node.bytes > 0) {
            total += node.bytes;
          }
        }
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
    }
    return total;
  }

  Future<bool> _confirmBackupCapacity(BackupRequest request) async {
    int? estimatedBytes;
    try {
      estimatedBytes = await _estimateSourceBytes(request.data.id, request.path);
    } catch (_) {
      // An estimate is advisory; a transient listing error must not prevent a backup.
    }
    if (!mounted) return false;

    final repo = _repo;
    final hasQuota = repo != null && repo.maxBytes > 0;
    final freeBytes = hasQuota ? (repo.maxBytes - repo.usedBytes).clamp(0, repo.maxBytes) : null;
    final likelyTight = estimatedBytes != null && freeBytes != null && estimatedBytes > freeBytes;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Review Backup Size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Source: ${request.data.name}${request.path == '/' ? '' : request.path}'),
              const SizedBox(height: 12),
              Row(children: [
                const Expanded(child: Text('Estimated source data')),
                Text(estimatedBytes == null ? 'Unavailable' : fmtBytes(estimatedBytes)),
              ]),
              if (freeBytes != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Expanded(child: Text('Vault space available')),
                  Text(fmtBytes(freeBytes)),
                ]),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Vault capacity is not reported as a fixed quota.'),
                ),
              if (likelyTight) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'The source size exceeds the reported free space. This backup may run out of room.',
                    style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                estimatedBytes == null
                    ? 'Could not estimate the folder size. You can still start the backup.'
                    : 'This is the uncompressed source size, not the space the snapshot will use. Compression and deduplication can reduce repository growth, so the estimate is advisory.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start Backup')),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _backup() async {
    final repo = _repo;
    if (repo == null) return;
    final datas = await guarded(context, () => _v.datas(limit: 200));
    if (datas == null || !mounted) return;
    if (datas.items.isEmpty) return toast(context, 'Create a data folder first', error: true);
    final req = await showBackupSheet(context, datas: datas.items, repos: [repo], repo: repo);
    if (req == null || !mounted) return;
    final proceed = await _confirmBackupCapacity(req);
    if (!proceed || !mounted) return;
    final j = await guarded(context, () => _v.backup(widget.repoId, req.toBody()));
    if (j != null) _queued(j);
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
    final f = await formDialog(context, 'Update Vault Password', [
      const FieldSpec('cur', 'Current Password', kind: 'secret', required: true),
      const FieldSpec('new', 'New Password', kind: 'secret', required: true),
    ], intro: 'Updates the password Vaulton uses to open this vault. It doesn’t change the vault’s encryption.');
    if (f == null) return;
    await guarded(context, () => _v.changeRepoPassword(widget.repoId, f['cur']!, f['new']!));
    if (mounted) toast(context, 'Password updated');
  }

  Widget _menu() => PopupMenuButton<String>(
        onSelected: (a) {
          switch (a) {
            case 'check': _healthCheck();
            case 'clean': _retention();
            case 'pw': _password();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'check', child: Text('Run Health Check')),
          PopupMenuItem(value: 'clean', child: Text('Clean Up Old Snapshots…')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'pw', child: Text('Update Vault Password…')),
        ],
      );

  /// Storage + the two actions people want most. Used as the list header on phones
  /// and as the sidebar on desktop.
  Widget _summary() {
    final r = _repo;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    Widget label(String t) => Text(t, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (r == null)
            const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator())
          else ...[
            Row(children: [
              Expanded(child: Text('Storage', style: tt.titleSmall)),
              Align(
                alignment: Alignment.centerRight,
                child: chip(context, r.healthLabel, color: r.isError ? cs.errorContainer : null),
              ),
            ]),
            const SizedBox(height: 10),
            UsageBar(used: r.usedBytes, max: r.maxBytes),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text('${fmtBytes(r.usedBytes)} used', style: tt.bodyMedium),
                Text(r.maxBytes > 0 ? '${(r.usedBytes / r.maxBytes * 100).round()}% of ${fmtBytes(r.maxBytes)}' : 'No limit', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            if (r.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.error!, style: TextStyle(color: cs.error, fontSize: 12))),
            const SizedBox(height: 14),
          ],
          LayoutBuilder(builder: (context, c) {
            final backup = FilledButton.icon(onPressed: r == null ? null : _backup, icon: const Icon(Icons.backup_outlined), label: label('Backup'));
            final browse = OutlinedButton.icon(onPressed: r == null ? null : _browseLatest, icon: const Icon(Icons.folder_open_outlined), label: label('Browse'));
            if (c.maxWidth < 300) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [backup, const SizedBox(height: 8), browse]);
            }
            return Row(children: [Expanded(child: backup), const SizedBox(width: 8), Expanded(child: browse)]);
          }),
        ]),
      ),
    );
  }

  Widget _automation() => SchedulesList(
        repoId: widget.repoId,
        header: CleanupCard(key: _cleanupKey, repoId: widget.repoId, onRunNow: _retention),
      );

  TabBar _tabs() => TabBar(
        controller: _tc,
        isScrollable: false,
        tabAlignment: TabAlignment.fill,
        indicatorSize: TabBarIndicatorSize.tab,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        padding: EdgeInsets.zero,
        tabs: const [Tab(text: 'Snapshots'), Tab(text: 'Activity'), Tab(text: 'Automation')],
      );

  @override
  Widget build(BuildContext context) {
    final title = Text(_repo?.name ?? 'Backup Vault', maxLines: 1, overflow: TextOverflow.ellipsis);
    final wide = MediaQuery.sizeOf(context).width >= _kWideWidth;
    final cs = Theme.of(context).colorScheme;

    if (!wide) {
      return Scaffold(
        appBar: AppBar(title: title, actions: [_menu()], bottom: _tabs()),
        body: TabBarView(controller: _tc, children: [
          VaultTimeline(repoId: widget.repoId, repo: _repo, onBackup: _backup, snapshotOnly: true),
          VaultTimeline(repoId: widget.repoId, repo: _repo, onBackup: _backup, header: _summary()),
          _automation(),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title, actions: [_menu()]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWide),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: _kSidebarWidth, child: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 16), children: [_summary()])),
            VerticalDivider(width: 1, color: cs.outlineVariant),
            Expanded(
              child: Column(children: [
                _tabs(),
                Expanded(
                  child: TabBarView(controller: _tc, children: [
                    VaultTimeline(repoId: widget.repoId, repo: _repo, onBackup: _backup, snapshotOnly: true, showFab: false),
                    VaultTimeline(repoId: widget.repoId, repo: _repo, onBackup: _backup, showFab: false),
                    _automation(),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
