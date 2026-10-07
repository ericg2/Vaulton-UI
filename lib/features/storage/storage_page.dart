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
import '../transfers/transfer_manager.dart';
import 'root_shares_page.dart';
import 'share_logic.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key, this.initialTab = 0, this.onBoundarySwipe});
  final int initialTab;
  final ValueChanged<int>? onBoundarySwipe;
  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  int _lastBoundaryDirection = 0;
  DateTime _lastBoundaryAt = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab.clamp(0, 2).toInt(),
        child: Scaffold(
          appBar: AppBar(title: const Text('Storage'), bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Locations'),
            Tab(text: 'Data Folders'),
            Tab(text: 'Backup Vaults'),
          ])),
          body: NotificationListener<OverscrollNotification>(onNotification: (n) {
          if (n.metrics.axis != Axis.horizontal || !n.metrics.atEdge || n.overscroll == 0) return false;
          final direction = n.overscroll > 0 ? 1 : -1;
          final now = DateTime.now();
          if (direction != _lastBoundaryDirection || now.difference(_lastBoundaryAt) > const Duration(milliseconds: 500)) {
            _lastBoundaryDirection = direction;
            _lastBoundaryAt = now;
            widget.onBoundarySwipe?.call(direction);
          }
          return false;
        }, child: const TabBarView(children: [_RootsTab(), PointsTab(repo: false), PointsTab(repo: true)])),
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
    final r = await formDialog(context, 'New Location', [
      const FieldSpec('name', 'Name', required: true),
      FieldSpec('scheme', 'Storage type', kind: 'choice', options: kSourceSchemas.keys.toList(), initial: 'fs'),
      const FieldSpec('capacity', 'Capacity', kind: 'capacity', required: true),
      const FieldSpec('data', 'Allow data folders', kind: 'bool', initial: 'true'),
      const FieldSpec('repo', 'Allow backup vaults', kind: 'bool', initial: 'true'),
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
      if (mounted) toast(context, 'Location created');
    }
  }

  Future<void> _edit(Root root) async {
    final r = await formDialog(context, 'Edit ${root.name}', [
      FieldSpec('name', 'Name', initial: root.name, required: true),
      FieldSpec('capacity', 'Capacity', kind: 'capacity', initial: bytesToGb(root.maxBytes), required: true),
      FieldSpec('data', 'Allow data folders', kind: 'bool', initial: '${root.isDataAllowed}'),
      FieldSpec('repo', 'Allow backup vaults', kind: 'bool', initial: '${root.isRepoAllowed}'),
    ]);
    if (r == null) return;
    await guarded(context, () => _v.patchRoot(root.id, {
          'name': r['name'], 'maxBytes': int.tryParse(r['capacity'] ?? '') ?? 0, 'isDataAllowed': r['data'] == 'true', 'isRepoAllowed': r['repo'] == 'true'}));
    _key.currentState?.refresh();
  }

  Future<void> _editSource(Root root) async {
    final scheme = '${root.source?['scheme'] ?? ''}';
    if (!kSourceSchemas.containsKey(scheme)) return toast(context, 'Unknown connection type', error: true);
    final src = await _sourceForm(scheme, root.source);
    if (src == null) return;
    await guarded(context, () => _v.patchRoot(root.id, {'source': src}));
    _key.currentState?.refresh();
  }

  Future<void> _shares(Root root) async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RootSharesPage(root: root)));
    _key.currentState?.silentRefresh(force: true);
  }

  /// Tapping a location shows what it is, who can use it, and what you can do with it.
  void _openRoot(Root root) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetCtx) {
        void then(VoidCallback run) {
          Navigator.pop(sheetCtx);
          run();
        }

        return _RootSheet(
          root: root,
          vaulton: _v,
          onShare: () => then(() => _shares(root)),
          onEdit: () => then(() => _edit(root)),
          onEditConnection: () => then(() => _editSource(root)),
          onDelete: () => then(() => _delete(root)),
        );
      },
    );
  }

  Future<void> _delete(Root root) async {
    if (!await confirm(context, 'Delete location “${root.name}”?', 'Refused while it still contains data or backup vault points. Files in the underlying storage are not erased.', ok: 'Delete', danger: true)) return;
    await guarded(context, () => _v.deleteRoot(root.id));
    _key.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(epochProvider, (_, _) => _key.currentState?.silentRefresh(force: true));
    final u = ref.watch(userProvider)!;
    final canCreate = u.has(Scopes.rootsManage);
    return Scaffold(
      floatingActionButton: canCreate ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New Location')) : null,
      body: CursorList<Root>(
        key: _key,
        empty: 'No storage locations.',
        emptyHint: canCreate ? 'A location is where your data is stored, such as a disk, network share or cloud account. Tap “New location” to connect one.' : 'Ask an administrator to share a storage location with you.',
        emptyIcon: Icons.storage_outlined,
        autoRefresh: const Duration(seconds: 8),
        fetch: (c) => _v.roots(cursor: c),
        itemBuilder: (ctx, r, i) {
          final used = r.maxBytes - r.freeBytes;
          final scheme = '${r.source?['scheme'] ?? ''}';
          return Card(
            child: InkWell(
              onTap: () => _openRoot(r),
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
                  if (r.isDataAllowed) chip(ctx, 'Data Folders'),
                  if (r.isRepoAllowed) chip(ctx, 'Backup Vaults'),
                ]),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.only(right: 12), child: UsageBar(used: used, max: r.maxBytes)),
                const SizedBox(height: 4),
                Text('${fmtBytes(used < 0 ? 0 : used)} allocated · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}', style: Theme.of(ctx).textTheme.bodySmall),
              ]),
            ),
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
    if (usable.isEmpty) return toast(context, 'No location allows ${widget.repo ? 'backup vaults' : 'data folders'}. Create or share one first.', error: true);
    final labels = {for (final r in usable) '${r.name}${usable.where((x) => x.name == r.name).length > 1 ? ' (${r.id.substring(0, 6)})' : ''}': r};
    final storageInfo = usable.map((r) {
      final used = (r.maxBytes - r.freeBytes).clamp(0, r.maxBytes > 0 ? r.maxBytes : 1 << 62);
      return '${r.name}: ${fmtBytes(used)} used · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}';
    }).join('\\n');
    final f = await formDialog(context, 'New ${widget.repo ? 'Backup Vault' : 'Data Folder'}', [
      FieldSpec('root', 'Location', kind: 'choice', options: labels.keys.toList()),
      const FieldSpec('name', 'Name', required: true),
      FieldSpec('capacity', 'Space Limit', kind: 'capacity', required: true, maxBytes: usable.map((r) => r.maxBytes).where((x) => x > 0).fold<int?>(null, (m, x) => m == null || x > m ? x : m)),
      if (widget.repo) const FieldSpec('pw', 'Vault Password (at least 8 characters)', kind: 'secret', required: true),
    ], ok: 'Create', intro: 'Available storage:\\n$storageInfo\\n\\nSet the space limit based on how much data you expect to store. It cannot exceed the location limit.');
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
      FieldSpec('capacity', 'Space Limit', kind: 'capacity', initial: bytesToGb(p.maxBytes), required: true, maxBytes: root.maxBytes > 0 ? root.maxBytes : null),
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
    if (!widget.repo) ref.read(transferProvider.notifier).clearForPoint(p.id);
    _key.currentState?.refresh();
    ref.invalidate(pointNamesProvider);
    ref.read(epochProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    // Upload / delete / move finished somewhere else: refresh usage numbers in place.
    ref.listen(epochProvider, (_, _) {
      _key.currentState?.silentRefresh(force: true);
      _loadRoots();
    });
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: Text('New ${widget.repo ? 'Backup Vault' : 'Data Folder'}')),
      body: CursorList<Point>(
        key: _key,
        empty: 'No ${widget.repo ? 'backup vaults' : 'data folders'} yet',
        emptyHint: widget.repo ? 'A backup vault stores your backups. Tap “New Backup Vault” to create one.' : 'A data folder stores your files. Set its space limit when you create it.',
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
            OutlinedButton.icon(onPressed: () => _openRepo(p, tab: 0), icon: const Icon(Icons.camera_alt_outlined), label: const Text('Snapshots')),
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
      child: InkWell(
        onTap: () => widget.repo ? _openRepo(p) : Navigator.push(ctx, MaterialPageRoute(builder: (_) => FilesPage(initialPointId: p.id))),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(widget.repo ? Icons.inventory_2_outlined : Icons.folder_outlined),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: Theme.of(ctx).textTheme.titleMedium),
              Text(
                'Location: ${_roots.where((r) => r.id == p.rootId).map((r) => r.name).firstOrNull ??
    (p.rootId.length > 8 ? p.rootId.substring(0, 8) : p.rootId)}',                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ])),
            PopupMenuButton<String>(
              onSelected: (a) => a == 'edit' ? _edit(p) : _delete(p),
              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Rename or Change Limit')), PopupMenuItem(value: 'del', child: Text('Delete'))],
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
      ),
    );
  }
}


/// Everything that has touched one data folder, with a one-tap backup button.
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


/// Details for one storage location, including who it is shared with.
class _RootSheet extends StatefulWidget {
  const _RootSheet({required this.root, required this.vaulton, required this.onShare, required this.onEdit, required this.onEditConnection, required this.onDelete});
  final Root root;
  final Vaulton vaulton;
  final VoidCallback onShare, onEdit, onEditConnection, onDelete;
  @override
  State<_RootSheet> createState() => _RootSheetState();
}

class _RootSheetState extends State<_RootSheet> {
  List<Json>? _shares;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.root.isOwner) {
      widget.vaulton.shares(widget.root.id).then((v) {
        if (mounted) setState(() => _shares = v);
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
    }
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.root;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final used = (r.maxBytes - r.freeBytes).clamp(0, r.maxBytes > 0 ? r.maxBytes : 1 << 62).toInt();
    final scheme = '${r.source?['scheme'] ?? ''}'.toUpperCase();
    final holds = [if (r.isDataAllowed) 'Data folders', if (r.isRepoAllowed) 'Backup vaults'];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: cs.secondaryContainer, child: Icon(Icons.dns_outlined, color: cs.onSecondaryContainer)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(r.isOwner ? 'Owned by You' : 'Shared with you by ${r.userName}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        UsageBar(used: used, max: r.maxBytes),
        const SizedBox(height: 6),
        Text('${fmtBytes(used)} used · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}', style: t.bodySmall),
        const SizedBox(height: 8),
        if (scheme.isNotEmpty) _row(Icons.cable_outlined, 'Connection Type', scheme),
        _row(Icons.inventory_2_outlined, 'Can Hold', holds.isEmpty ? 'Nothing Yet' : holds.join(' and ')),
        const Divider(height: 28),
        Text('Who Can Use It', style: t.titleSmall),
        const SizedBox(height: 8),
        if (!r.isOwner)
          Text('Only the owner can manage access.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
        else if (_failed)
          Text('Couldn’t load sharing details.', style: t.bodyMedium?.copyWith(color: cs.error))
        else if (_shares == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
        else if (_shares!.isEmpty)
          Text('Not shared with anyone yet. Only you can use this location.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
        else
          for (final s in _shares!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(radius: 16, child: Text('${s['userName']}'.isEmpty ? '?' : '${s['userName']}'[0].toUpperCase())),
              title: Text('${s['userName']}'),
              trailing: Text('Up to ${fmtBytes(toInt(s['maxBytes']))}', style: t.bodySmall),
            ),
        if (r.isOwner) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.onShare,
              icon: const Icon(Icons.group_add_outlined),
              label: Text(_shares != null && _shares!.isNotEmpty ? 'Manage Sharing' : 'Share This Location'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('Edit Details')),
            OutlinedButton.icon(onPressed: widget.onEditConnection, icon: const Icon(Icons.link), label: const Text('Edit Connection')),
            TextButton.icon(
              onPressed: widget.onDelete,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ]),
        ],
      ]),
    );
  }
}
