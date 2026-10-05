import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/source_schemas.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../backups/backup_flow.dart';
import '../backups/jobs_page.dart';
import '../backups/repo_page.dart';
import '../backups/snapshot_browser.dart';
import '../files/files_page.dart';
import 'root_shares_page.dart';
import 'share_logic.dart';

class StoragePage extends StatelessWidget {
  const StoragePage({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(title: const Text('Storage'), bottom: const TabBar(tabs: [
            Tab(text: 'Roots'),
            Tab(text: 'Data Points'),
            Tab(text: 'Repositories'),
          ])),
          body: const TabBarView(children: [_RootsTab(), PointsTab(repo: false), PointsTab(repo: true)]),
        ),
      );
}

// ================================================================== ROOTS
class _RootsTab extends ConsumerStatefulWidget {
  const _RootsTab();
  @override
  ConsumerState<_RootsTab> createState() => _RootsTabState();
}

class _RootsTabState extends ConsumerState<_RootsTab> {
  final _key = GlobalKey<CursorListState<Root>>();
  Vaulton get _v => ref.read(vaultonProvider);

  Future<Map<String, dynamic>?> _sourceForm(String scheme, Map<String, dynamic>? existing) async {
    final fields = kSourceSchemas[scheme]!;
    final r = await formDialog(
      context,
      '${scheme.toUpperCase()} Connection',
      [
        for (final f in fields)
          FieldSpec(f.key, pretty(f.key),
              kind: f.kind == 'b' ? 'bool' : (f.kind == 'k' ? 'secret' : 'text'),
              required: f.required && f.kind != 'k' || (f.required && existing == null),
              initial: existing?[f.key] == null || f.kind == 'k' ? '' : '${existing![f.key]}'),
      ],
      ok: 'Continue',
      intro: existing != null ? 'Leave secret fields empty to keep them unchanged only if the server supports partial updates; otherwise re-enter them.' : null,
    );
    if (r == null) return null;
    final src = <String, dynamic>{'scheme': scheme};
    for (final f in fields) {
      final val = r[f.key]!;
      if (f.kind == 'b') {
        src[f.key] = val == 'true';
      } else if (val.isNotEmpty) {
        src[f.key] = val;
      }
    }
    return src;
  }

  Future<void> _create() async {
    final r = await formDialog(context, 'New Root', [
      const FieldSpec('name', 'Name', required: true),
      FieldSpec('scheme', 'Storage Type', kind: 'choice', options: kSourceSchemas.keys.toList(), initial: 'fs'),
      const FieldSpec('capacity', 'Capacity', kind: 'capacity', required: true),
      const FieldSpec('data', 'Allow Data Points', kind: 'bool', initial: 'true'),
      const FieldSpec('repo', 'Allow Repositories', kind: 'bool', initial: 'true'),
    ], ok: 'Next');
    if (r == null || !mounted) return;
    final src = await _sourceForm(r['scheme']!, null);
    if (src == null) return;
    final created = await guarded(context, () => _v.createRoot({
          'name': r['name'],
          'source': src,
          'maxBytes': int.tryParse(r['capacity'] ?? '') ?? 0,
          'isDataAllowed': r['data'] == 'true',
          'isRepoAllowed': r['repo'] == 'true',
        }));
    if (created != null) {
      _key.currentState?.refresh();
      if (mounted) toast(context, 'Root Created');
    }
  }

  Future<void> _edit(Root root) async {
    final r = await formDialog(context, 'Edit ${root.name}', [
      FieldSpec('name', 'Name', initial: root.name, required: true),
      FieldSpec('capacity', 'Capacity', kind: 'capacity', initial: bytesToGb(root.maxBytes), required: true),
      FieldSpec('data', 'Allow Data Points', kind: 'bool', initial: '${root.isDataAllowed}'),
      FieldSpec('repo', 'Allow Repositories', kind: 'bool', initial: '${root.isRepoAllowed}'),
    ]);
    if (r == null) return;
    await guarded(context, () => _v.patchRoot(root.id, {
          'name': r['name'], 'maxBytes': int.tryParse(r['capacity'] ?? '') ?? 0, 'isDataAllowed': r['data'] == 'true', 'isRepoAllowed': r['repo'] == 'true'}));
    _key.currentState?.refresh();
  }

  Future<void> _editSource(Root root) async {
    final scheme = '${root.source?['scheme'] ?? ''}';
    if (!kSourceSchemas.containsKey(scheme)) return toast(context, 'Unknown Storage Type', error: true);
    final src = await _sourceForm(scheme, root.source);
    if (src == null) return;
    await guarded(context, () => _v.patchRoot(root.id, {'source': src}));
    _key.currentState?.refresh();
  }

  Future<void> _shares(Root root) =>
      Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RootSharesPage(root: root)));

  Future<void> _delete(Root root) async {
    if (!await confirm(context, 'Delete root “${root.name}”?', 'Refused while it still contains data or repository points. Files in the underlying storage are not erased.', ok: 'Delete', danger: true)) return;
    await guarded(context, () => _v.deleteRoot(root.id));
    _key.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final u = ref.watch(userProvider)!;
    final canCreate = u.has(Scopes.rootsManage);
    return Scaffold(
      floatingActionButton: canCreate ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New Root')) : null,
      body: CursorList<Root>(
        key: _key,
        empty: 'No Storage Roots',
        emptyIcon: Icons.storage_outlined,
        autoRefresh: const Duration(seconds: 8),
        fetch: (c) => _v.roots(cursor: c),
        itemBuilder: (ctx, r, i) {
          final used = r.maxBytes - r.freeBytes;
          final scheme = '${r.source?['scheme'] ?? ''}';
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.dns_outlined),
                  const SizedBox(width: 12),
                  Expanded(child: Text(r.name, style: Theme.of(ctx).textTheme.titleMedium)),
                  if (r.isOwner)
                    PopupMenuButton<String>(
                      onSelected: (a) {
                        switch (a) {
                          case 'edit': _edit(r);
                          case 'src': _editSource(r);
                          case 'share': _shares(r);
                          case 'del': _delete(r);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'src', child: Text('Edit Connection')),
                        PopupMenuItem(value: 'share', child: Text('Sharing…')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'del', child: Text('Delete')),
                      ],
                    ),
                ]),
                Wrap(children: [
                  if (scheme.isNotEmpty) chip(ctx, scheme.toUpperCase()),
                  chip(ctx, r.isOwner ? 'Owner' : 'Shared by ${r.userName}'),
                  if (r.isDataAllowed) chip(ctx, 'Data Points'),
                  if (r.isRepoAllowed) chip(ctx, 'Repositories'),
                ]),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.only(right: 12), child: UsageBar(used: used, max: r.maxBytes)),
                const SizedBox(height: 4),
                Text('${fmtBytes(used < 0 ? 0 : used)} allocated · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}', style: Theme.of(ctx).textTheme.bodySmall),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ================================================================= POINTS
class PointsTab extends ConsumerStatefulWidget {
  const PointsTab({super.key, required this.repo});
  final bool repo;
  @override
  ConsumerState<PointsTab> createState() => _PointsTabState();
}

class _PointsTabState extends ConsumerState<PointsTab> {
  final _key = GlobalKey<CursorListState<Point>>();
  Vaulton get _v => ref.read(vaultonProvider);
  String get _noun => widget.repo ? 'Repository' : 'Data Point';
  List<Root> _roots = const [];

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    try {
      final roots = await _v.roots(limit: 200);
      if (mounted) setState(() => _roots = roots.items);
    } catch (_) {}
  }

  Future<void> _create() async {
    final roots = await guarded(context, () => _v.roots(limit: 200));
    if (roots == null || !mounted) return;
    final usable = roots.items.where((r) => widget.repo ? r.isRepoAllowed : r.isDataAllowed).toList();
    if (usable.isEmpty) return toast(context, 'No root allows ${widget.repo ? 'repositories' : 'data points'}. Create or share one first.', error: true);
    final labels = {for (final r in usable) '${r.name}${usable.where((x) => x.name == r.name).length > 1 ? ' (${r.id.substring(0, 6)})' : ''}': r};
    final f = await formDialog(context, 'New $_noun', [
      FieldSpec('root', 'Root', kind: 'choice', options: labels.keys.toList()),
      const FieldSpec('name', 'Name', required: true),
      FieldSpec('capacity', 'Quota', kind: 'capacity', required: true, maxBytes: usable.map((r) => r.maxBytes).where((x) => x > 0).fold<int?>(null, (m, x) => m == null || x > m ? x : m)),
      if (widget.repo) const FieldSpec('pw', 'Repository Password (Min 8)', kind: 'secret', required: true),
    ], ok: 'Create');
    if (f == null) return;
    final body = {'rootId': labels[f['root']]!.id, 'name': f['name'], 'maxBytes': int.tryParse(f['capacity'] ?? '') ?? 0, if (widget.repo) 'password': f['pw']};
    await guarded(context, () => widget.repo ? _v.createRepo(body) : _v.createData(body));
    _key.currentState?.refresh();
    ref.invalidate(pointNamesProvider);
    ref.read(epochProvider.notifier).bump();
  }

  Future<void> _edit(Point p) async {
    final root = await guarded(context, () => _v.root(p.rootId));
    if (root == null || !mounted) return;
    final f = await formDialog(context, 'Edit ${p.name}', [
      FieldSpec('name', 'Name', initial: p.name, required: true),
      FieldSpec('capacity', 'Quota', kind: 'capacity', initial: bytesToGb(p.maxBytes), required: true, maxBytes: root.maxBytes > 0 ? root.maxBytes : null),
    ]);
    if (f == null) return;
    final body = {'name': f['name'], 'maxBytes': int.tryParse(f['capacity'] ?? '') ?? 0};
    await guarded(context, () => widget.repo ? _v.patchRepo(p.id, body) : _v.patchData(p.id, body));
    _key.currentState?.refresh();
  }

  Future<void> _delete(Point p) async {
    if (!await confirm(context, 'Delete “${p.name}”?',
        widget.repo ? 'Its schedules and job history are deleted. Backups already stored are not erased.' : 'Its schedules are deleted. Files in the underlying storage are not erased.',
        ok: 'Delete', danger: true)) {
      return;
    }
    await guarded(context, () => widget.repo ? _v.deleteRepo(p.id) : _v.deleteData(p.id));
    _key.currentState?.refresh();
    ref.invalidate(pointNamesProvider);
    ref.read(epochProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: Text('New $_noun')),
      body: CursorList<Point>(
        key: _key,
        empty: 'No ${widget.repo ? 'Repositories' : 'Data Points'} Yet',
        emptyIcon: widget.repo ? Icons.inventory_2_outlined : Icons.folder_outlined,
        autoRefresh: const Duration(seconds: 5),
        fetch: (c) => widget.repo ? _v.repos(cursor: c) : _v.datas(cursor: c),
        itemBuilder: (ctx, p, i) => _pointCard(ctx, p),
      ),
    );
  }

  void _openRepo(Point p, {int tab = 0}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => RepoPage(repoId: p.id, repo: p, initialTab: tab)));

  Widget _pointCard(BuildContext ctx, Point p) {
    final cs = Theme.of(ctx).colorScheme;
    final actions = widget.repo
        ? <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: p))),
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse'),
            ),
            FilledButton.icon(onPressed: () => startBackup(ctx, ref, repo: p), icon: const Icon(Icons.backup_outlined), label: const Text('Backup Here')),
            OutlinedButton.icon(onPressed: () => _openRepo(p), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Snapshots')),
            OutlinedButton.icon(onPressed: () => _openRepo(p, tab: 1), icon: const Icon(Icons.work_history_outlined), label: const Text('Jobs')),
            OutlinedButton.icon(onPressed: () => _openRepo(p, tab: 2), icon: const Icon(Icons.schedule), label: const Text('Schedules')),
          ]
        : <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => FilesPage(initialPointId: p.id))),
              icon: const Icon(Icons.folder_open),
              label: const Text('Open Files'),
            ),
            FilledButton.icon(onPressed: () => startBackup(ctx, ref, data: p), icon: const Icon(Icons.backup_outlined), label: const Text('Backup')),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => DataJobsPage(data: p))),
              icon: const Icon(Icons.history),
              label: const Text('Jobs'),
            ),
          ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widget.repo ? Icons.inventory_2_outlined : Icons.folder_outlined),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: Theme.of(ctx).textTheme.titleMedium),
              Text(
                'Root: ${_roots.where((r) => r.id == p.rootId).map((r) => r.name).firstOrNull ?? (p.rootId.length > 8 ? p.rootId.substring(0, 8) : p.rootId)}',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ])),
            PopupMenuButton<String>(
              onSelected: (a) => a == 'edit' ? _edit(p) : _delete(p),
              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Rename / Quota')), PopupMenuItem(value: 'del', child: Text('Delete'))],
            ),
          ]),
          Wrap(children: [chip(ctx, p.healthLabel, color: p.isError ? cs.errorContainer : null)]),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.only(right: 8), child: UsageBar(used: p.usedBytes, max: p.maxBytes)),
          const SizedBox(height: 4),
          Text('${fmtBytes(p.usedBytes)} of ${fmtBytes(p.maxBytes)}', style: Theme.of(ctx).textTheme.bodySmall),
          if (p.error != null) Text(p.error!, style: TextStyle(color: cs.error, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ]),
      ),
    );
  }
}


/// Everything that has touched one data point, with a one-tap backup button.
class DataJobsPage extends ConsumerWidget {
  const DataJobsPage({super.key, required this.data});
  final Point data;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text('Jobs · ${data.name}')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => startBackup(context, ref, data: data),
          icon: const Icon(Icons.backup),
          label: const Text('Backup'),
        ),
        body: JobsList(dataId: data.id),
      );
}
