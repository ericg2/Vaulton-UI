import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

/// Desktop / wide layout: a normal tabbed page.
class StoragePage extends StatelessWidget {
  const StoragePage({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        initialIndex: initialTab.clamp(0, 2).toInt(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Storage'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Data Folders'),
              Tab(text: 'Backup Vaults'),
              Tab(text: 'Locations'),
            ]),
          ),
          body: const TabBarView(children: [PointsTab(repo: false), PointsTab(repo: true), RootsTab()]),
        ),
      );
}

/// Phone layout: each storage tab is its own page in the shell's PageView, so one
/// continuous swipe moves Dashboard > Files > Transfers > Data Folders > Backup Vaults >
/// Locations > More with no nested scrolling to fight.
class StorageSection extends StatelessWidget {
  const StorageSection({super.key, required this.index, required this.pages, required this.basePage, required this.onSelect});
  final int index, basePage;
  final PageController pages;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Storage'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: StorageTabStrip(pages: pages, basePage: basePage, onSelect: onSelect),
          ),
        ),
        body: switch (index) {
          0 => const PointsTab(repo: false),
          1 => const PointsTab(repo: true),
          _ => const RootsTab(),
        },
      );
}

/// Tab strip whose indicator follows the finger while the shell's pages are swiped.
class StorageTabStrip extends StatelessWidget {
  const StorageTabStrip({super.key, required this.pages, required this.basePage, required this.onSelect});
  final PageController pages;
  final int basePage;
  final ValueChanged<int> onSelect;
  static const _labels = ['Data Folders', 'Backup Vaults', 'Locations'];

  double _position() {
    if (!pages.hasClients || !pages.position.haveDimensions) return pages.initialPage.toDouble();
    return pages.page ?? pages.initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: AnimatedBuilder(
        animation: pages,
        builder: (context, _) {
          final t = (_position() - basePage).clamp(0.0, 2.0);
          return LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / 3;
            const barW = 56.0;
            return Stack(children: [
              Row(children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(
                    width: w,
                    child: InkWell(
                      onTap: () => onSelect(i),
                      child: Center(
                        child: Text(
                          _labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Color.lerp(cs.onSurfaceVariant, cs.primary, (1 - (t - i).abs()).clamp(0.0, 1.0)),
                              ),
                        ),
                      ),
                    ),
                  ),
              ]),
              Positioned(
                left: t * w + (w - barW) / 2,
                bottom: 0,
                child: Container(
                  width: barW,
                  height: 3,
                  decoration: BoxDecoration(color: cs.primary, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                ),
              ),
            ]);
          });
        },
      ),
    );
  }
}

// ================================================================== ROOTS
class RootsTab extends ConsumerStatefulWidget {
  const RootsTab({super.key});
  @override
  ConsumerState<RootsTab> createState() => _RootsTabState();
}

class _RootsTabState extends ConsumerState<RootsTab> {
  final _key = GlobalKey<CursorListState<Root>>();
  Vaulton get _v => ref.read(vaultonProvider);

  Future<String?> _pickLocalPath(String? initialPath) async {
    Json? current;
    var loading = true;
    var started = false;
    String? error;
    final startPath = initialPath?.trim() ?? '';

    Future<void> load(String? path, void Function(void Function()) update) async {
      update(() { loading = true; error = null; });
      try {
        final result = await _v.browseLocal(path);
        update(() { current = result; loading = false; });
      } catch (e) {
        update(() { error = e.toString(); loading = false; });
      }
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, update) {
          if (current == null && loading && !started) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted && current == null && loading) {
                load(startPath.isEmpty ? null : startPath, update);
              }
            });
          }
          final dirs = (current?['directories'] as List? ?? const []).map(toJson).toList();
          final path = '${current?['currentPath'] ?? ''}';
          final parent = toStr(current?['parentPath']);
          final available = toInt(current?['availableBytes']);
          final total = toInt(current?['capacityBytes']);
          return AlertDialog(
            title: const Text('Choose Directory'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(path.isEmpty ? 'Drives' : path, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.titleSmall),
                if (available > 0) Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Text('${fmtBytes(available)} available of ${fmtBytes(total)}',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
                const Divider(),
                Expanded(child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? Center(child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)))
                        : dirs.isEmpty
                            ? const Center(child: Text('No subdirectories found.'))
                            : ListView.builder(
                                itemCount: dirs.length,
                                itemBuilder: (_, i) {
                                  final d = dirs[i];
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.folder_outlined),
                                    title: Text('${d['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    onTap: () => load('${d['path']}', update),
                                  );
                                },
                              )),
                if (!loading && error == null) TextButton.icon(
                  onPressed: parent == null || parent.isEmpty ? null : () => load(parent, update),
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Parent Folder'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: path.isEmpty ? null : () => Navigator.pop(dialogContext, path),
                icon: const Icon(Icons.check),
                label: const Text('Select Folder'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _sourceForm(String scheme, Map<String, dynamic>? existing) async {
    final fields = kSourceSchemas[scheme]!;
    final r = await formDialog(
      context,
      '${scheme.toUpperCase()} Connection',
      [
        for (final f in fields)
          FieldSpec(f.key, pretty(f.key),
              kind: scheme == 'fs' && f.key == 'root' ? 'path' : (f.kind == 'b' ? 'bool' : (f.kind == 'k' ? 'secret' : 'text')),
              required: f.required && f.kind != 'k' || (f.required && existing == null),
              initial: existing?[f.key] == null || f.kind == 'k' ? '' : '${existing![f.key]}'),
      ],
      ok: 'Continue',
      intro: existing != null ? 'Re-enter secret fields unless the server keeps existing values.' : null,
      pick: scheme == 'fs' ? (values) => _pickLocalPath(values['root']) : null,
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
    final details = await formDialog(context, 'New Location', [
      const FieldSpec('name', 'Name', required: true),
      FieldSpec('scheme', 'Storage Type', kind: 'choice', options: kSourceSchemas.keys.toList(), initial: 'fs'),
      const FieldSpec('data', 'Allow Data Folders', kind: 'bool', initial: 'true'),
      const FieldSpec('repo', 'Allow Backup Vaults', kind: 'bool', initial: 'true'),
    ], ok: 'Continue', intro: 'A location is a storage area. Data folders and backup vaults each receive a limit from its capacity.');
    if (details == null || !mounted) return;
    final src = await _sourceForm(details['scheme']!, null);
    if (src == null || !mounted) return;
    Json? detected;
    if (details['scheme'] == 'fs') {
      detected = await guarded(context, () => _v.browseLocal(src['root'] as String?));
      if (detected == null || !mounted) return;
    }
    final available = toInt(detected?['availableBytes']);
    final total = toInt(detected?['capacityBytes']);
    final initialCapacity = available > 0 ? bytesToCapacity(available, 'GiB') : '';
    final capacity = await formDialog(
      context,
      'Location Capacity',
      [
        FieldSpec('capacity', 'Location Capacity', kind: 'capacity', initial: initialCapacity, required: true,
          initialUnit: 'GiB'),
      ],
      ok: 'Create Location',
      intro: detected == null
          ? 'Set the maximum capacity Vaulton may allocate to this location.'
          : 'Drive: ${fmtBytes(total)} total, ${fmtBytes(available)} free. Set Vaulton’s location capacity; it can exceed the detected free space.',
    );
    if (capacity == null || !mounted) return;
    final maxBytes = int.tryParse(capacity['capacity'] ?? '');
    if (maxBytes == null || maxBytes <= 0) return toast(context, 'Enter a valid capacity.', error: true);
    final created = await guarded(context, () => _v.createRoot({
      'name': details['name'],
      'source': src,
      'maxBytes': maxBytes,
      'isDataAllowed': details['data'] == 'true',
      'isRepoAllowed': details['repo'] == 'true',
    }));
    if (created != null) {
      _key.currentState?.refresh();
      if (mounted) toast(context, 'Location created');
    }
  }

  Future<void> _edit(Root root) async {
    final r = await formDialog(context, 'Edit ${root.name}', [
      FieldSpec('name', 'Name', initial: root.name, required: true),
      FieldSpec('capacity', 'Capacity', kind: 'capacity', initial: bytesToGb(root.maxBytes), required: true, initialBytes: root.maxBytes),
      FieldSpec('data', 'Allow Data Folders', kind: 'bool', initial: '${root.isDataAllowed}'),
      FieldSpec('repo', 'Allow Backup Vaults', kind: 'bool', initial: '${root.isRepoAllowed}'),
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
    if (!await confirm(context, 'Delete location “${root.name}”?', 'Not allowed while it still holds data folders or backup vaults. Files in the underlying storage are kept.', ok: 'Delete', danger: true)) return;
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
        empty: 'No locations yet',
        emptyHint: canCreate ? 'A location is where your data lives: a disk, network share or cloud account.' : 'Ask an administrator to share a location with you.',
        emptyIcon: Icons.storage_outlined,
        autoRefresh: const Duration(seconds: 8),
        fetch: (c) => _v.roots(cursor: c),
        itemBuilder: (ctx, r, i) {
          final allocated = r.allocatedBytes;
          final scheme = '${r.source?['scheme'] ?? ''}';
          return Card(
            child: InkWell(
              onTap: () => _openRoot(r),
              child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.dns_outlined, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 16),
                  Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(ctx).textTheme.titleMedium)),
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
                        PopupMenuItem(value: 'share', child: Text('Share')),
                        PopupMenuDivider(),
                        PopupMenuItem(value: 'del', child: Text('Delete')),
                      ],
                    ),
                ]),
                Padding(padding: const EdgeInsets.only(right: 12), child: Wrap(children: [
                  if (scheme.isNotEmpty) chip(ctx, scheme.toUpperCase()),
                  chip(ctx, r.isOwner ? 'Owner' : 'Shared by ${r.userName}'),
                  if (r.isDataAllowed) chip(ctx, 'Data Folders'),
                  if (r.isRepoAllowed) chip(ctx, 'Backup Vaults'),
                ])),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.only(right: 12), child: UsageBar(used: allocated, max: r.maxBytes)),
                const SizedBox(height: 6),
                Padding(padding: const EdgeInsets.only(right: 12), child: Text(r.isOwner ? '${fmtBytes(allocated)} allocated · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}' : '${fmtBytes(allocated)} allocated of ${fmtBytes(r.maxBytes)} total', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
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
    if (usable.isEmpty) return toast(context, 'No location allows ${widget.repo ? 'backup vaults' : 'data folders'}. Add or share one first.', error: true);
    final created = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true, constraints: const BoxConstraints(maxWidth: 640), builder: (_) => _NewPointSheet(repo: widget.repo, roots: usable, vaulton: _v));
    if (created == true && mounted) { _key.currentState?.refresh(); ref.invalidate(pointNamesProvider); ref.read(epochProvider.notifier).bump(); }
  }

  Future<void> _edit(Point p) async {
    final root = await guarded(context, () => _v.root(p.rootId));
    if (root == null || !mounted) return;
    final f = await formDialog(context, 'Edit ${p.name}', [
      FieldSpec('name', 'Name', initial: p.name, required: true),
      FieldSpec('capacity', 'Space Limit', kind: 'capacity', initial: bytesToGb(p.maxBytes), required: true, maxBytes: root.maxBytes > 0 ? root.maxBytes : null, initialBytes: p.maxBytes),
    ]);
    if (f == null) return;
    final body = {'name': f['name'], 'maxBytes': int.tryParse(f['capacity'] ?? '') ?? 0};
    await guarded(context, () => widget.repo ? _v.patchRepo(p.id, body) : _v.patchData(p.id, body));
    _key.currentState?.refresh();
  }

  Future<void> _delete(Point p) async {
    if (!await confirm(context, 'Delete “${p.name}”?',
        widget.repo ? 'Its schedules and job history are removed. Stored backups are kept.' : 'Its schedules are removed. Files in the underlying storage are kept.',
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
        emptyHint: widget.repo ? 'A backup vault stores your backups.' : 'A data folder stores your files.',
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
    final tt = Theme.of(ctx).textTheme;
    final locationName = _roots.where((r) => r.id == p.rootId).map((r) => r.name).firstOrNull ?? (p.rootId.length > 8 ? p.rootId.substring(0, 8) : p.rootId);
    final actions = widget.repo
        ? <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => SnapshotBrowserPage(repo: p))),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Browse'),
            ),
            FilledButton.icon(onPressed: () => startBackup(ctx, ref, repo: p), icon: const Icon(Icons.backup_outlined), label: const Text('Backup')),
          ]
        : <Widget>[
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => FilesPage(initialPointId: p.id))),
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Open'),
            ),
            FilledButton.icon(onPressed: () => startBackup(ctx, ref, data: p), icon: const Icon(Icons.backup_outlined), label: const Text('Backup')),
          ];
    return Card(
      child: InkWell(
        onTap: () {
          if (widget.repo) {
            _openRepo(p);
          } else {
            Navigator.push(ctx, MaterialPageRoute(builder: (_) => FilesPage(initialPointId: p.id)));
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(widget.repo ? Icons.inventory_2_outlined : Icons.folder_outlined, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium),
                  Text(locationName, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              chip(ctx, p.healthLabel, color: p.isError ? cs.errorContainer : null, inline: true),
              PopupMenuButton<String>(
                onSelected: (a) {
                  switch (a) {
                    case 'edit': _edit(p);
                    case 'jobs':
                      if (widget.repo) {
                        _openRepo(p, tab: 1);
                      } else {
                        Navigator.push(ctx, MaterialPageRoute(builder: (_) => DataJobsPage(data: p)));
                      }
                    case 'snaps': _openRepo(p, tab: 0);
                    case 'sched': _openRepo(p, tab: 2);
                    case 'del': _delete(p);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (widget.repo) const PopupMenuItem(value: 'snaps', child: Text('Snapshots')),
                  const PopupMenuItem(value: 'jobs', child: Text('Jobs')),
                  if (widget.repo) const PopupMenuItem(value: 'sched', child: Text('Schedules')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'del', child: Text('Delete')),
                ],
              ),
            ]),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                UsageBar(used: p.usedBytes, max: p.maxBytes),
                const SizedBox(height: 6),
                Text('${fmtBytes(p.usedBytes)} of ${fmtBytes(p.maxBytes)}', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (p.error != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.error!, style: TextStyle(color: cs.error, fontSize: 12))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: actions[0]),
                  const SizedBox(width: 8),
                  Expanded(child: actions[1]),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}


class _NewPointSheet extends StatefulWidget {
  const _NewPointSheet({required this.repo, required this.roots, required this.vaulton});
  final bool repo; final List<Root> roots; final Vaulton vaulton;
  @override State<_NewPointSheet> createState() => _NewPointSheetState();
}
class _NewPointSheetState extends State<_NewPointSheet> {
  late Root _root;
  final _name = TextEditingController(), _capacity = TextEditingController(), _password = TextEditingController();
  String _unit = 'GiB';
  bool _showPassword = false, _saving = false, _capacityTouched = false, _passwordTouched = false;
  int? _exactCapacityBytes;
  String? _exactCapacityText, _exactCapacityUnit;

  @override
  void initState() {
    super.initState();
    _root = widget.roots.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _password.dispose();
    super.dispose();
  }

  int get _capacityBytesValue {
    if (_exactCapacityBytes != null &&
        _capacity.text.trim() == _exactCapacityText &&
        _unit == _exactCapacityUnit) {
      return _exactCapacityBytes!;
    }
    final n = double.tryParse(_capacity.text.trim().replaceAll(',', '.'));
    if (n == null || !n.isFinite || n < 0) return 0;
    return (n * (capacityFactors[_unit] ?? capacityFactors['GiB']!)).round();
  }

  void _clearExactCapacity() {
    _exactCapacityBytes = null;
    _exactCapacityText = null;
    _exactCapacityUnit = null;
  }

  void _setExactCapacity(int bytes) {
    _capacity.text = bytesToCapacity(bytes, _unit);
    _exactCapacityBytes = bytes;
    _exactCapacityText = _capacity.text.trim();
    _exactCapacityUnit = _unit;
  }

  String get _capacityError {
    final raw = _capacity.text.trim();
    if (raw.isEmpty) return 'Enter a space limit.';
    final n = double.tryParse(raw.replaceAll(',', '.'));
    if (n == null || !n.isFinite || n < 0 || _capacityBytesValue < 4096) {
      return 'Enter a valid space limit.';
    }
    if (_root.freeBytes <= 0) return 'No allocatable capacity remains for you on this location.';
    if (_capacityBytesValue > _root.freeBytes) {
      return 'The limit exceeds the capacity available to you on this location.';
    }
    return '';
  }
  String get _passwordError=>widget.repo&&_password.text.length<8?'Use at least 8 characters.':'';
  Future<void> _save() async {
    final name = _name.text.trim();
    setState(() { _capacityTouched = true; _passwordTouched = true; });
    if (name.isEmpty || _capacityError.isNotEmpty || _passwordError.isNotEmpty) return;
    final maxBytes = _capacityBytesValue;
    setState(() => _saving = true);
    try { await (widget.repo?widget.vaulton.createRepo({'rootId':_root.id,'name':name,'maxBytes':maxBytes,'password':_password.text}):widget.vaulton.createData({'rootId':_root.id,'name':name,'maxBytes':maxBytes})); if(mounted)Navigator.pop(context,true); }
    catch(e){if(mounted){setState(()=>_saving=false);toast(context,e.toString(),error:true);}}
  }
  @override Widget build(BuildContext context){
    final cs=Theme.of(context).colorScheme,t=Theme.of(context).textTheme;
    return Padding(padding:EdgeInsets.fromLTRB(20,4,20,MediaQuery.viewInsetsOf(context).bottom+20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[CircleAvatar(radius:25,backgroundColor:widget.repo?cs.secondaryContainer:cs.primaryContainer,child:Icon(widget.repo?Icons.inventory_2_outlined:Icons.folder_outlined,color:widget.repo?cs.onSecondaryContainer:cs.onPrimaryContainer)),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(widget.repo?'New Backup Vault':'New Data Folder',style:t.headlineSmall),const SizedBox(height:2),Text(widget.repo?'An encrypted place for your backups.':'A dedicated space for your files.',style:t.bodyMedium?.copyWith(color:cs.onSurfaceVariant))]))]),
      const SizedBox(height:20),Text('Location',style:t.titleSmall),const SizedBox(height:8),
      DropdownButtonFormField<Root>(initialValue:_root,isExpanded:true,decoration:const InputDecoration(border:OutlineInputBorder(),prefixIcon:Icon(Icons.dns_outlined)),items:[for(final r in widget.roots)DropdownMenuItem(value:r,child:Text(r.name,overflow:TextOverflow.ellipsis))],onChanged:_saving?null:(r)=>setState(()=>_root=r!)),
      const SizedBox(height:6),Text(_root.isOwner ? '${fmtBytes(_root.allocatedBytes)} allocated · ${fmtBytes(_root.freeBytes)} free of ${fmtBytes(_root.maxBytes)}' : '${fmtBytes(_root.allocatedBytes)} allocated of ${fmtBytes(_root.maxBytes)} total',style:t.bodySmall?.copyWith(color:cs.onSurfaceVariant)),
      const SizedBox(height:18),TextField(controller:_name,enabled:!_saving,textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Name',hintText:'e.g. Documents',border:OutlineInputBorder())),
      const SizedBox(height:16),Text('Space Limit',style:t.titleSmall),const SizedBox(height:8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: _capacity,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {
              _clearExactCapacity();
              _capacityTouched = true;
            }),
            decoration: InputDecoration(
              labelText: 'Amount',
              border: const OutlineInputBorder(),
              errorText: (!_capacityTouched || _capacityError.isEmpty) ? null : _capacityError,
              helperText: _capacityBytesValue > 0
                  ? 'Exact: ${NumberFormat.decimalPattern().format(_capacityBytesValue)} bytes'
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 105,
          child: DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Unit'),
            items: const [
              DropdownMenuItem(value: 'GiB', child: Text('GiB')),
              DropdownMenuItem(value: 'TiB', child: Text('TiB')),
            ],
            onChanged: _saving ? null : (v) {
              if (v == null) return;
              final raw = double.tryParse(_capacity.text.trim().replaceAll(',', '.'));
              final valid = _capacity.text.trim().isEmpty ||
                  (raw != null && raw.isFinite && raw >= 0);
              final bytes = _capacityBytesValue;
              setState(() {
                _unit = v;
                if (valid) {
                  _setExactCapacity(bytes);
                } else {
                  _clearExactCapacity();
                }
              });
            },
          ),
        ),
      ]),
      if(_root.freeBytes>0)...[
        const SizedBox(height:8),
        Row(children:[
          Text('Allocation',style:t.bodySmall?.copyWith(color:cs.onSurfaceVariant)),
          const Spacer(),
          Text('${((_capacityBytesValue/_root.freeBytes)*100).clamp(0,100).round()}%',style:t.titleSmall),
        ]),
        Slider(
          value:(_capacityBytesValue/_root.freeBytes).clamp(0,1).toDouble(),
          min:0,max:1,divisions:100,
          label:'${((_capacityBytesValue/_root.freeBytes)*100).clamp(0,100).round()}%',
          onChanged: _saving ? null : (v) {
            final bytes = (v * _root.freeBytes).round();
            setState(() {
              _capacityTouched = true;
              _setExactCapacity(bytes);
            });
          },
        ),
        Text('Available to allocate: ${fmtBytes(_root.freeBytes)}',style:t.bodySmall?.copyWith(color:cs.onSurfaceVariant)),
      ],
      if(widget.repo)...[const SizedBox(height:18),TextField(controller:_password,enabled:!_saving,obscureText:!_showPassword,onChanged:(_)=>setState((){_passwordTouched=true;}),decoration:InputDecoration(labelText:'Vault Password',hintText:'At least 8 characters',border:const OutlineInputBorder(),errorText:(!_passwordTouched||_passwordError.isEmpty)?null:_passwordError,suffixIcon:IconButton(tooltip:_showPassword?'Hide Password':'Show Password',icon:Icon(_showPassword?Icons.visibility_off_outlined:Icons.visibility_outlined),onPressed:_saving?null:()=>setState(()=>_showPassword=!_showPassword)))),const SizedBox(height:6),Text('This password is required to open the backup vault.',style:t.bodySmall?.copyWith(color:cs.onSurfaceVariant))],
      const SizedBox(height:20),Row(children:[Expanded(child:OutlinedButton(onPressed:_saving?null:()=>Navigator.pop(context),child:const Text('Cancel'))),const SizedBox(width:10),Expanded(child:FilledButton.icon(onPressed:_saving?null:_save,icon:_saving?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.check),label:Text(_saving?'Creating…':'Create')))])
    ])));
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
    final allocated = r.allocatedBytes;
    final availableLabel = r.isOwner ? 'free' : 'available to you';
    final scheme = '${r.source?['scheme'] ?? ''}'.toUpperCase();
    final holds = [if (r.isDataAllowed) 'Data Folders', if (r.isRepoAllowed) 'Backup Vaults'];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(backgroundColor: cs.secondaryContainer, child: Icon(Icons.dns_outlined, color: cs.onSecondaryContainer)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(r.isOwner ? 'Owned by You' : 'Shared by ${r.userName}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        UsageBar(used: allocated, max: r.maxBytes),
        const SizedBox(height: 6),
        Text(r.isOwner ? '${fmtBytes(allocated)} allocated · ${fmtBytes(r.freeBytes)} free of ${fmtBytes(r.maxBytes)}' : '${fmtBytes(r.freeBytes)} available to you', style: t.bodySmall),
        const SizedBox(height: 8),
        if (scheme.isNotEmpty) _row(Icons.cable_outlined, 'Connection Type', scheme),
        _row(Icons.inventory_2_outlined, 'Can Hold', holds.isEmpty ? 'Nothing Yet' : holds.join(' and ')),
        const Divider(height: 28),
        Text('Who Can Use It', style: t.titleSmall),
        const SizedBox(height: 8),
        if (!r.isOwner)
          Text('Only the owner can manage access.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
        else if (_failed)
          Text('Couldn’t load sharing.', style: t.bodyMedium?.copyWith(color: cs.error))
        else if (_shares == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
        else if (_shares!.isEmpty)
          Text('Not shared. Only you can use this location.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
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
