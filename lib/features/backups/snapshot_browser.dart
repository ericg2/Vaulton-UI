import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import '../files/files_page.dart' show iconFor;
import '../files/folder_picker.dart';
import '../files/download_location.dart';
import '../files/preview_page.dart';
import '../transfers/download_sheet.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfers_page.dart';
import 'job_detail_page.dart';
import 'job_widgets.dart';

/// Browse the contents of a backup vault snapshot, download files/folders or restore them.
class SnapshotBrowserPage extends ConsumerStatefulWidget {
  const SnapshotBrowserPage({super.key, required this.repo, this.snapshotId});
  final Point repo;

  /// Full id, unique prefix, or null for the newest snapshot.
  final String? snapshotId;

  @override
  ConsumerState<SnapshotBrowserPage> createState() => _SnapshotBrowserPageState();
}

typedef _Crumb = ({String name, String path});

typedef SnapshotRestoreTarget = ({String path, bool isDir, String name});

class SnapshotLockBadge extends StatelessWidget {
  const SnapshotLockBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('Locked', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.error, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

Future<void> restoreSnapshotFlow({
  required BuildContext context,
  required Vaulton vaulton,
  required Point repo,
  required Snapshot snapshot,
  List<SnapshotRestoreTarget>? targets,
}) async {
  final selected = targets ?? await showDialog<List<SnapshotRestoreTarget>>(
    context: context,
    builder: (_) => _SnapshotPathPickerDialog(repo: repo, snapshot: snapshot),
  );
  if (selected == null || selected.isEmpty || !context.mounted) return;

  final dest = await pickFolder(context, title: 'Restore into…');
  if (dest == null || !context.mounted) return;

  final label = selected.length == 1 ? selected.first.name : '${selected.length} items';
  final f = await formDialog(
    context,
    'Restore $label',
    [
      const FieldSpec('delete', 'Delete extra files in the destination', kind: 'bool'),
      const FieldSpec('dry', 'Test run only', kind: 'bool'),
    ],
    ok: 'Restore',
    intro: 'From snapshot: ${selected.map((x) => x.path).join(', ')}\n'
        'To: ${dest.point.name}${dest.path == '/' ? '' : dest.path}\n'
        'Folders are restored into a subfolder with their own name; existing files with the same name may be overwritten.',
  );
  if (f == null) return;

  RepoJob? last;
  var queued = 0;
  for (final t in selected) {
    final job = await guarded(
      context,
      () => vaulton.restore(repo.id, {
        'dataId': dest.point.id,
        'snapshotId': snapshot.id,
        'snapshotPath': t.path,
        'outputPath': t.isDir && t.path != '/' ? joinPath(dest.path, t.name) : dest.path,
        'delete': f['delete'] == 'true',
        'dryRun': f['dry'] == 'true',
      }),
    );
    if (job == null) break;
    last = job;
    queued++;
  }
  if (!context.mounted || last == null) return;
  if (queued == 1) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: last!.id)));
  } else {
    toast(context, 'Queued $queued restore jobs — follow them under Jobs');
  }
}

class _SnapshotPathPickerDialog extends ConsumerStatefulWidget {
  const _SnapshotPathPickerDialog({required this.repo, required this.snapshot});
  final Point repo;
  final Snapshot snapshot;

  @override
  ConsumerState<_SnapshotPathPickerDialog> createState() => _SnapshotPathPickerDialogState();
}

class _SnapshotPathPickerDialogState extends ConsumerState<_SnapshotPathPickerDialog> {
  String _path = '/';
  List<Node>? _items;
  Object? _error;

  String _join(String base, String name) => base == '/' ? '/$name' : '$base/$name';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _items = null; _error = null; });
    try {
      final out = <Node>[];
      String? cursor;
      do {
        final page = await ref.read(vaultonProvider).browseSnapshot(widget.repo.id, widget.snapshot.id, path: _path, cursor: cursor, limit: 200);
        out.addAll(page.items);
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
      if (mounted) setState(() => _items = out);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _choose(Node n) {
    Navigator.pop<List<SnapshotRestoreTarget>>(context, [(path: _join(_path, n.name), isDir: n.isDir, name: n.name)]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose snapshot path'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(children: [
          Row(children: [
            IconButton(
              tooltip: 'Up',
              onPressed: _path == '/' ? null : () { setState(() => _path = parentPath(_path)); _load(); },
              icon: const Icon(Icons.arrow_upward),
            ),
            Expanded(child: Text(_path, overflow: TextOverflow.ellipsis)),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(
                context,
                [(path: _path, isDir: true, name: _path == '/' ? 'snapshot' : baseName(_path))],
              ),
              child: const Text('Select folder'),
            ),
          ]),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? ErrorView(_error!, onRetry: _load)
                : _items == null
                    ? const Center(child: CircularProgressIndicator())
                    : _items!.isEmpty
                        ? const EmptyView('This snapshot folder is empty', icon: Icons.folder_open)
                        : ListView.builder(
                            itemCount: _items!.length,
                            itemBuilder: (_, i) {
                              final n = _items![i];
                              return ListTile(
                                leading: Icon(iconFor(n), color: n.isDir ? Theme.of(context).colorScheme.primary : null),
                                title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(n.isDir ? 'Folder' : fmtBytes(n.bytes)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  if (n.isDir) {
                                    setState(() => _path = _join(_path, n.name));
                                    _load();
                                  } else {
                                    _choose(n);
                                  }
                                },
                              );
                            },
                          ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

class _SnapshotBrowserPageState extends ConsumerState<SnapshotBrowserPage> {
  List<Snapshot>? _snaps;
  Snapshot? _snap;
  Object? _error;
  final List<_Crumb> _trail = [];
  final Set<String> _sel = {};
  List<Node> _loaded = [];
  String _search = '';
  bool _searching = false, _desc = false, _locking = false;
  int _reload = 0;
  final _searchCtl = TextEditingController();

  Vaulton get _v => ref.read(vaultonProvider);
  TransferManager get _mgr => ref.read(transferProvider.notifier);
  String? get _cur => _trail.isEmpty ? null : _trail.last.path;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Loads snapshots. With [keep], the snapshot with the same time stays selected
  /// (locking changes a snapshot's id, so the id can't be used).
  Future<void> _init({Snapshot? keep}) async {
    setState(() => _error = null);
    try {
      final pg = await _v.snapshots(widget.repo.id, limit: 100);
      var list = pg.items;
      Snapshot? pick;
      if (keep?.time != null) pick = list.where((s) => s.time == keep!.time).firstOrNull;
      final want = widget.snapshotId;
      if (pick == null && keep == null && want != null && want.isNotEmpty && want != 'latest') {
        pick = list.where((s) => s.id == want || s.id.startsWith(want)).firstOrNull;
        if (pick == null) {
          pick = (await _v.snapshots(widget.repo.id, idPrefix: want, limit: 1)).items.firstOrNull;
          if (pick != null) list = [pick, ...list];
        }
      }
      pick ??= list.firstOrNull;
      if (!mounted) return;
      setState(() {
        _snaps = list;
        _snap = pick;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _snapLabel(Snapshot s) => '${fmtDate(s.time)}  ·  ${shortId(s.id)}';

  Widget _snapshotDropdownLabel(Snapshot s) => Row(children: [
        Expanded(child: Text(_snapLabel(s), overflow: TextOverflow.ellipsis)),
        if (s.locked) const SnapshotLockBadge(),
      ]);

  Future<void> _toggleLock() async {
    final snap = _snap;
    if (snap == null || _locking) return;
    setState(() => _locking = true);
    try {
      final locked = !snap.locked;
      final result = await guarded(context, () => _v.lockSnapshot(widget.repo.id, snap.id, locked));
      if (result == null || !mounted) return;
      toast(context, toStr(result['message']) ?? (locked ? 'Snapshot locked' : 'Snapshot unlocked'));
      await _init(keep: snap);
    } finally {
      if (mounted) setState(() => _locking = false);
    }
  }

  void _go(List<_Crumb> trail) => setState(() {
        _trail
          ..clear()
          ..addAll(trail);
        _sel.clear();
        _search = '';
        _searching = false;
        _searchCtl.clear();
      });

  void _toggle(Node n) => setState(() {
        if (!_sel.remove(n.name)) _sel.add(n.name);
      });

  List<Node> get _selected => _loaded.where((n) => _sel.contains(n.name)).toList();

  // --------------------------------------------------------------- actions
  void _open(Node n) {
    if (n.isDir) return _go([..._trail, (name: n.name, path: n.pathIn(_cur))]);
    if (canPreview(n.name, n.bytes)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewPage(
            pointId: widget.repo.id,
            snapshotId: _snap!.id,
            path: n.pathIn(_cur),
            name: n.name,
            onDownload: () => _download([n]),
          ),
        ),
      );
    } else {
      _info(n);
    }
  }

  Future<void> _download(List<Node> nodes) async {
    final snap = _snap!;
    try {
      final root = await chooseDownloadBase(context, ref);
      if (root == null || !mounted) return;
      final stamp = snap.time == null ? shortId(snap.id) : DateFormat('yyyy-MM-dd_HHmm').format(snap.time!);
      final base = p.join(root, widget.repo.name, stamp, p.joinAll(_trail.map((t) => t.name)));
      final ids = <String>[];

      void enqueue(String path, String rel, int size) {
        final t = _mgr.addDownload(
          pointId: widget.repo.id,
          snapshotId: snap.id,
          remotePath: path,
          name: baseName(path),
          localPath: p.join(base, p.joinAll(rel.split('/'))),
          size: size,
        );
        if (t != null) ids.add(t.id);
      }

      Future<void> walk(String dirPath, String rel) async {
        String? cursor;
        do {
          final pg = await _v.browseSnapshot(widget.repo.id, snap.id, path: dirPath, cursor: cursor);
          for (final n in pg.items) {
            final np = n.pathIn(dirPath);
            if (n.isDir) {
              await walk(np, '$rel/${n.name}');
            } else {
              enqueue(np, '$rel/${n.name}', n.bytes);
            }
          }
          cursor = pg.hasMore ? pg.nextCursor : null;
        } while (cursor != null);
      }

      for (final n in nodes) {
        if (n.isDir) {
          if (mounted) toast(context, 'Reading folder “${n.name}”…');
          await walk(n.pathIn(_cur), n.name);
        } else {
          enqueue(n.pathIn(_cur), n.name, n.bytes);
        }
      }
      if (!mounted) return;
      setState(_sel.clear);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (ids.isEmpty) {
        toast(context, 'Nothing new to download. These files are already queued.');
      } else {
        showDownloadSheet(context, ids, onOpenTransfers: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransfersPage())));
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Restores [targets] using the same source/destination/options flow as the backup vault-level restore.
  Future<void> _restore(List<SnapshotRestoreTarget> targets) async {
    await restoreSnapshotFlow(
      context: context,
      vaulton: _v,
      repo: widget.repo,
      snapshot: _snap!,
      targets: targets,
    );
    if (mounted) setState(_sel.clear);
  }

  void _info(Node n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n.name, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText('Path: ${n.pathIn(_cur)}'),
          if (!n.isDir) Text('Size: ${fmtBytes(n.bytes)}'),
          Text('Modified: ${fmtDate(n.modified)}'),
          Text('Snapshot: ${_snapLabel(_snap!)}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          OutlinedButton.icon(
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('Restore…'),
            onPressed: () {
              Navigator.pop(ctx);
              _restore([(path: n.pathIn(_cur), isDir: n.isDir, name: n.name)]);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download'),
            onPressed: () {
              Navigator.pop(ctx);
              _download([n]);
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final title = Text(widget.repo.name, overflow: TextOverflow.ellipsis);
    if (_error != null) return Scaffold(appBar: AppBar(title: title), body: ErrorView(_error!, onRetry: _init));
    if (_snaps == null) return Scaffold(appBar: AppBar(title: title), body: const Center(child: CircularProgressIndicator()));
    if (_snap == null) {
      return Scaffold(appBar: AppBar(title: title), body: const EmptyView('This backup vault has no snapshots yet.\nRun a backup first.', icon: Icons.camera_alt_outlined));
    }
    final snap = _snap!;
    final selecting = _sel.isNotEmpty;

    final appBar = selecting
        ? AppBar(
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
            title: Text('${_sel.length} selected'),
            actions: [
              IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all), onPressed: () => setState(() => _sel.addAll(_loaded.map((n) => n.name)))),
              IconButton(tooltip: 'Download', icon: const Icon(Icons.download), onPressed: () => _download(_selected)),
              IconButton(
                tooltip: 'Restore…',
                icon: const Icon(Icons.settings_backup_restore),
                onPressed: () => _restore([for (final n in _selected) (path: n.pathIn(_cur), isDir: n.isDir, name: n.name)]),
              ),
            ],
          )
        : AppBar(
            title: _searching
                ? TextField(
                    controller: _searchCtl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search this folder', border: InputBorder.none),
                    onSubmitted: (v) => setState(() => _search = v.trim()),
                  )
                : title,
            bottom: _locking ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null,
            actions: [
              IconButton(
                tooltip: _locking ? (snap.locked ? 'Unlocking…' : 'Locking…') : (snap.locked ? 'Unlock Snapshot' : 'Lock Snapshot'),
                icon: _locking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(snap.locked ? Icons.lock_open_outlined : Icons.lock_outline),
                onPressed: _locking ? null : _toggleLock,
              ),
              IconButton(
                tooltip: 'Search',
                icon: Icon(_searching ? Icons.search_off : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _search = '';
                    _searchCtl.clear();
                  }
                }),
              ),
              IconButton(tooltip: _desc ? 'Descending' : 'Ascending', icon: Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward), onPressed: () => setState(() => _desc = !_desc)),
              IconButton(
                tooltip: 'Restore this folder…',
                icon: const Icon(Icons.settings_backup_restore),
                onPressed: () => _restore([(path: _cur ?? '/', isDir: true, name: _trail.isEmpty ? 'snapshot' : _trail.last.name)]),
              ),
              IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => setState(() => _reload++)),
            ],
          );

    return PopScope(
      canPop: _trail.isEmpty && !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          setState(_sel.clear);
        } else {
          _go(_trail.sublist(0, _trail.length - 1));
        }
      },
      child: Scaffold(
        appBar: appBar,
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(children: [
              const Icon(Icons.camera_alt_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: snap.id,
                    borderRadius: BorderRadius.circular(12),
                    items: [for (final s in _snaps!) DropdownMenuItem(value: s.id, child: _snapshotDropdownLabel(s))],
                    onChanged: (id) {
                      setState(() => _snap = _snaps!.firstWhere((s) => s.id == id));
                      _go(List.of(_trail));
                    },
                  ),
                ),
              ),
              if (snap.tags.isNotEmpty && MediaQuery.sizeOf(context).width > 600) chip(context, '#${snap.tags.first}'),
            ]),
          ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
              for (var i = 0; i <= _trail.length; i++) ...[
                if (i > 0) const Icon(Icons.chevron_right, size: 18),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: i == _trail.length ? null : () => _go(_trail.sublist(0, i)),
                  child: Text(i == 0 ? 'Snapshot' : _trail[i - 1].name),
                ),
              ],
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: CursorList<Node>(
              key: ValueKey('${snap.id}|${_cur ?? ''}|$_search|$_desc|$_reload'),
              empty: _search.isEmpty ? 'This folder is empty' : 'No matches',
              emptyIcon: Icons.folder_open,
              fetch: (c) => _v.browseSnapshot(widget.repo.id, snap.id, path: _cur, search: _search, cursor: c, order: _desc ? 'Desc' : 'Asc'),
              onChanged: (l) => _loaded = l,
              itemBuilder: (c, n, i) {
                final sel = _sel.contains(n.name);
                final explicitSelection = kIsWeb || isDesktop;
                return ListTile(
                  selected: sel,
                  leading: explicitSelection || selecting
                      ? Checkbox(value: sel, onChanged: (_) => _toggle(n))
                      : Icon(iconFor(n), color: n.isDir ? Theme.of(context).colorScheme.primary : null),
                  title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(n.isDir ? fmtShort(n.modified) : '${fmtBytes(n.bytes)} · ${fmtShort(n.modified)}'),
                  trailing: selecting
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (a) {
                            switch (a) {
                              case 'open': _open(n);
                              case 'download': _download([n]);
                              case 'restore': _restore([(path: n.pathIn(_cur), isDir: n.isDir, name: n.name)]);
                              case 'select': _toggle(n);
                              case 'info': _info(n);
                              case 'copy': copyText(context, n.pathIn(_cur), 'Path copied');
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'open', child: Text('Open')),
                            PopupMenuItem(value: 'download', child: Text('Download')),
                            PopupMenuItem(value: 'restore', child: Text('Restore…')),
                            PopupMenuItem(value: 'select', child: Text('Select')),
                            PopupMenuItem(value: 'info', child: Text('Details')),
                            PopupMenuItem(value: 'copy', child: Text('Copy path')),
                          ],
                        ),
                  onTap: () => (kIsWeb || isDesktop) ? _open(n) : (selecting ? _toggle(n) : _open(n)),
                  onLongPress: () => _toggle(n),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
