import 'dart:async';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import '../../platform/local_files.dart';
import '../transfers/transfer_manager.dart';
import '../transfers/transfer_models.dart';
import 'file_ops.dart';
import 'folder_picker.dart';
import 'preview_page.dart';

IconData iconFor(Node n) {
  if (n.isDir) return Icons.folder;
  switch (extOf(n.name)) {
    case 'png': case 'jpg': case 'jpeg': case 'gif': case 'webp': case 'bmp': case 'heic': case 'svg':
      return Icons.image_outlined;
    case 'mp4': case 'mkv': case 'mov': case 'avi': case 'webm':
      return Icons.movie_outlined;
    case 'mp3': case 'flac': case 'wav': case 'ogg': case 'm4a':
      return Icons.audiotrack_outlined;
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'zip': case 'tar': case 'gz': case '7z': case 'rar':
      return Icons.folder_zip_outlined;
    case 'txt': case 'md': case 'doc': case 'docx':
      return Icons.description_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key, this.initialPointId});

  /// Opens this data point first (used when navigating here from the Storage screen).
  final String? initialPointId;
  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  List<Point>? _points;
  Object? _pointsError;
  Point? _point;
  List<String> _segs = [];
  String _search = '';
  bool _searching = false, _desc = false, _drag = false;
  final Set<String> _sel = {};
  List<Node> _loaded = [];
  final _listKey = GlobalKey<CursorListState<Node>>();
  final _searchCtl = TextEditingController();
  Timer? _autoTimer;
  int _doneUploads = -1;
  DateTime _panelSince = DateTime.now();

  String get _path => _segs.isEmpty ? '/' : '/${_segs.join('/')}';
  Vaulton get _v => ref.read(vaultonProvider);
  TransferManager get _mgr => ref.read(transferProvider.notifier);

  @override
  void initState() {
    super.initState();
    _initPoints();
    // Reload the listing when an upload / move finishes, and quietly every 20s.
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && TickerMode.of(context) && _point != null) {
        _listKey.currentState?.refresh();
        _refreshUsage();
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _initPoints() async {
    setState(() => _pointsError = null);
    try {
      final pts = await loadAllPoints(ref);
      final last = widget.initialPointId ?? ref.read(settingsProvider).lastPointId;
      if (!mounted) return;
      setState(() {
        _points = pts;
        _point = pts.where((x) => x.id == last).firstOrNull ?? pts.firstOrNull;
      });
    } catch (e) {
      if (mounted) setState(() => _pointsError = e);
    }
  }

  void _go(List<String> segs) {
    setState(() {
      _segs = segs;
      _sel.clear();
      _search = '';
      _searching = false;
      _searchCtl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    _listKey.currentState?.refresh();
    _refreshUsage();
  }

  Future<void> _refreshUsage() async {
    final pt = _point;
    if (pt == null) return;
    try {
      final pg = await _v.datas(limit: 200);
      final fresh = pg.items.where((x) => x.id == pt.id).firstOrNull;
      if (fresh != null && mounted) setState(() => _point = fresh);
    } catch (_) {}
  }

  void _toggle(Node n) => setState(() {
        if (!_sel.remove(n.name)) _sel.add(n.name);
      });

  List<Node> get _selected => _loaded.where((n) => _sel.contains(n.name)).toList();

  // --------------------------------------------------------------- actions
  Future<void> _open(Node n) async {
    if (n.isDir) return _go([..._segs, n.name]);
    if (canPreview(n.name, n.bytes)) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(
            pointId: _point!.id, path: joinPath(_path, n.name), name: n.name, onDownload: () => _download([n]))));
    } else {
      _info(n);
    }
  }

  Future<void> _download(List<Node> nodes) async {
    final pt = _point!;
    try {
      final root = localFiles.supportsFilesystem
          ? (ref.read(settingsProvider).downloadDir ?? await localFiles.downloadsDir())
          : '';
      final base = p.join(root, pt.name, p.joinAll(_segs));
      var count = 0;
      for (final n in nodes) {
        if (!n.isDir) {
          _mgr.addDownload(pointId: pt.id, remotePath: joinPath(_path, n.name), name: n.name, localPath: p.join(base, n.name), size: n.bytes);
          count++;
        } else {
          if (mounted) toast(context, 'Reading folder “${n.name}”…');
          final files = await collectFiles(_v, pt.id, joinPath(_path, n.name), n.name);
          for (final f in files) {
            _mgr.addDownload(pointId: pt.id, remotePath: f.path, name: baseName(f.path), localPath: p.join(base, p.joinAll(f.relative.split('/'))), size: f.size);
            count++;
          }
        }
      }
      if (!mounted) return;
      setState(_sel.clear);
      toast(context, count == 0 ? 'Nothing to download' : 'Queued $count download${count == 1 ? '' : 's'}${localFiles.supportsFilesystem ? ' → $root' : ''}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(); // empty list when cancelled
    if (files.isEmpty) return;
    var n = 0;
    for (final f in files) {
      final remote = joinPath(_path, f.name);
      if (kIsWeb) {
        final bytes = await f.readAsBytes();
        _mgr.addUpload(pointId: _point!.id, remotePath: remote, bytes: bytes, size: bytes.length);
      } else if (f.path != null) {
        final size = f.lengthSync() ?? await f.length() ?? 0;
        _mgr.addUpload(pointId: _point!.id, remotePath: remote, localPath: f.path, size: size);
      } else {
        continue;
      }
      n++;
    }
    if (mounted) toast(context, 'Queued $n upload${n == 1 ? '' : 's'}');
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir != null) await _uploadDir(dir);
  }

  Future<void> _uploadDir(String dir) async {
    final entries = await localFiles.listRecursive(dir);
    final root = p.basename(dir);
    for (final e in entries) {
      _mgr.addUpload(pointId: _point!.id, remotePath: joinPath(joinPath(_path, root), e.relative), localPath: e.path, size: e.size);
    }
    if (mounted) toast(context, 'Queued ${entries.length} file${entries.length == 1 ? '' : 's'} from “$root”');
  }

  Future<void> _newFolder() async {
    final name = await promptText(context, 'New Folder', 'Folder Name', ok: 'Create');
    if (name == null) return;
    await guarded(context, () => _v.mkdir(_point!.id, joinPath(_path, name)));
    _refresh();
  }

  Future<void> _rename(Node n) async {
    final name = await promptText(context, 'Rename', 'New name', initial: n.name, ok: 'Rename');
    if (name == null || name == n.name) return;
    await _runTransfers([n], _point!.id, _path, copy: false, rename: name);
  }

  Future<void> _moveCopy(List<Node> nodes, bool copy) async {
    final dest = await pickFolder(context, initialPointId: _point!.id, initialPath: _path, title: copy ? 'Copy To…' : 'Move To…');
    if (dest == null) return;
    await _runTransfers(nodes, dest.point.id, dest.path, copy: copy);
  }

  Future<void> _runTransfers(List<Node> nodes, String dstPoint, String dstDir, {required bool copy, String? rename}) async {
    final pt = _point!;
    String? err;
    var i = 0;
    for (final n in nodes) {
      i++;
      if (nodes.length > 1 && mounted) toast(context, '${copy ? 'Copying' : 'Moving'} $i / ${nodes.length}…');
      try {
        final id = await _v.transfer(pt.id, joinPath(_path, n.name), dstPoint, joinPath(dstDir, rename ?? n.name), copy: copy);
        final r = await _v.awaitTransfer(id);
        if (r != null && r != 'timeout') err = r;
      } catch (e) {
        err = ApiException.from(e).message;
      }
      if (err != null) break;
    }
    if (!mounted) return;
    setState(_sel.clear);
    _refresh();
    if (err != null) {
      toast(context, err, error: true);
    } else {
      toast(context, rename != null ? 'Renamed' : (copy ? 'Copied' : 'Moved'));
    }
  }

  Future<void> _delete(List<Node> nodes) async {
    final dirs = nodes.where((n) => n.isDir).length;
    final ok = await confirm(context, 'Delete ${nodes.length} item${nodes.length == 1 ? '' : 's'}?',
        dirs > 0 ? 'Folders are deleted together with everything inside them. This cannot be undone.' : 'This cannot be undone.',
        ok: 'Delete', danger: true);
    if (!ok || !mounted) return;
    var cancelled = false;
    final progress = ValueNotifier<int>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Deleting…'),
        content: ValueListenableBuilder<int>(valueListenable: progress, builder: (_, n, _) => Text('$n item${n == 1 ? '' : 's'} deleted')),
        actions: [TextButton(onPressed: () => cancelled = true, child: const Text('Stop'))],
      ),
    );
    String? err;
    var done = 0;
    try {
      for (final n in nodes) {
        final base = done;
        done += await deleteRecursive(_v, _point!.id, joinPath(_path, n.name), n.isDir,
            onProgress: (c) => progress.value = base + c, cancelled: () => cancelled);
      }
    } catch (e) {
      err = ApiException.from(e).message;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(_sel.clear);
    _refresh();
    if (err != null && !cancelled) toast(context, err, error: true);
  }

  void _info(Node n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n.name, overflow: TextOverflow.ellipsis),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Path: ${joinPath(_path, n.name)}'),
          if (!n.isDir) Text('Size: ${fmtBytes(n.bytes)} (${n.bytes} bytes)'),
          Text('Modified: ${fmtDate(n.modified)}'),
          Text('Created: ${fmtDate(n.created)}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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

  void _addMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.upload_file), title: const Text('Upload Files'), onTap: () { Navigator.pop(ctx); _pickFiles(); }),
          if (isDesktop) ListTile(leading: const Icon(Icons.drive_folder_upload_outlined), title: const Text('Upload Folder'), onTap: () { Navigator.pop(ctx); _pickFolder(); }),
          ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: const Text('New Folder'), onTap: () { Navigator.pop(ctx); _newFolder(); }),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (_pointsError != null) {
      return Scaffold(appBar: AppBar(title: const Text('Files')), body: ErrorView(_pointsError!, onRetry: _initPoints));
    }
    if (_points == null) return Scaffold(appBar: AppBar(title: const Text('Files')), body: const Center(child: CircularProgressIndicator()));
    if (_point == null) {
      return Scaffold(appBar: AppBar(title: const Text('Files')),
          body: const EmptyView('No Data Points Yet.\nCreate one under Storage to start storing files.', icon: Icons.folder_off_outlined));
    }
    final pt = _point!;
    final selecting = _sel.isNotEmpty;
    // An upload to this data point just finished -> refresh the list automatically.
    final doneUploads = ref.watch(transferProvider.select((l) => l.where((t) => t.kind == TKind.upload && t.state == TState.done && t.pointId == pt.id).length));
    if (_doneUploads >= 0 && doneUploads != _doneUploads) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refresh();
          ref.read(epochProvider.notifier).bump();
        }
      });
    }
    _doneUploads = doneUploads;
    final ups = ref.watch(transferProvider).where((t) => t.kind == TKind.upload && t.pointId == pt.id && (t.active || t.createdAt.isAfter(_panelSince))).toList();
    final upActive = ups.where((t) => t.active).length;

    final appBar = selecting
        ? AppBar(
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
            title: Text('${_sel.length} selected'),
            actions: [
              IconButton(tooltip: 'Select All', icon: const Icon(Icons.select_all), onPressed: () => setState(() => _sel.addAll(_loaded.map((n) => n.name)))),
              IconButton(tooltip: 'Download', icon: const Icon(Icons.download), onPressed: () => _download(_selected)),
              IconButton(tooltip: 'Move', icon: const Icon(Icons.drive_file_move_outline), onPressed: () => _moveCopy(_selected, false)),
              IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy_outlined), onPressed: () => _moveCopy(_selected, true)),
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(_selected)),
            ],
          )
        : AppBar(
            title: _searching
                ? TextField(
                    controller: _searchCtl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search This Folder', border: InputBorder.none),
                    onSubmitted: (v) { setState(() => _search = v.trim()); _refresh(); },
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: pt.id,
                      borderRadius: BorderRadius.circular(12),
                      items: [for (final x in _points!) DropdownMenuItem(value: x.id, child: Text(x.name))],
                      onChanged: (id) {
                        ref.read(settingsProvider.notifier).setLastPoint(id!);
                        setState(() => _point = _points!.firstWhere((x) => x.id == id)); _refresh();
                        _go([]);
                      },
                    ),
                  ),
            actions: [
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
              IconButton(tooltip: _desc ? 'Descending' : 'Ascending', icon: Icon(_desc ? Icons.arrow_downward : Icons.arrow_upward), onPressed: () { setState(() => _desc = !_desc); _refresh(); }),
              if (upActive > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Tooltip(message: 'Uploading $upActive file${upActive == 1 ? '' : 's'}…', child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
                ),
              IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
            ],
          );

    return PopScope(
      canPop: _segs.isEmpty && !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          setState(_sel.clear);
        } else {
          _go(_segs.sublist(0, _segs.length - 1));
        }
      },
      child: Scaffold(
        appBar: appBar,
        floatingActionButton: selecting ? null : FloatingActionButton.extended(onPressed: _addMenu, icon: const Icon(Icons.add), label: const Text('Add')),
        body: DropTarget(
          onDragEntered: (_) => setState(() => _drag = true),
          onDragExited: (_) => setState(() => _drag = false),
          onDragDone: (d) async {
            setState(() => _drag = false);
            if (d.files.isNotEmpty) toast(context, 'Uploading ${d.files.length} item${d.files.length == 1 ? '' : 's'} to ${pt.name}…');
            for (final f in d.files) {
              if (kIsWeb) {
                _mgr.addUpload(pointId: pt.id, remotePath: joinPath(_path, f.name), bytes: await f.readAsBytes(), size: await f.length());
              } else if (await localFiles.isDirectory(f.path)) {
                await _uploadDir(f.path);
              } else {
                _mgr.addUpload(pointId: pt.id, remotePath: joinPath(_path, f.name), localPath: f.path, size: await f.length());
              }
            }
          },
          child: Stack(children: [
            Column(children: [
              _Breadcrumbs(point: pt, segs: _segs, onTap: (i) => _go(_segs.sublist(0, i))),
              if (upActive > 0) const LinearProgressIndicator(minHeight: 3),
              Expanded(
                child: CursorList<Node>(
                  key: _listKey,
                  empty: _search.isEmpty ? 'This Folder Is Empty' : 'No Matches',
                  emptyIcon: Icons.folder_open,
                  fetch: (c) => _v.list(pt.id, _path, search: _search, cursor: c, order: _desc ? 'Desc' : 'Asc'),
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
                                  case 'rename': _rename(n);
                                  case 'move': _moveCopy([n], false);
                                  case 'copy': _moveCopy([n], true);
                                  case 'select': _toggle(n);
                                  case 'info': _info(n);
                                  case 'delete': _delete([n]);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'open', child: Text('Open')),
                                PopupMenuItem(value: 'download', child: Text('Download')),
                                PopupMenuItem(value: 'rename', child: Text('Rename')),
                                PopupMenuItem(value: 'move', child: Text('Move To…')),
                                PopupMenuItem(value: 'copy', child: Text('Copy To…')),
                                PopupMenuItem(value: 'select', child: Text('Select')),
                                PopupMenuItem(value: 'info', child: Text('Details')),
                                PopupMenuDivider(),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                      onTap: () => (kIsWeb || isDesktop) ? _open(n) : (selecting ? _toggle(n) : _open(n)),
                      onLongPress: () => _toggle(n),
                    );
                  },
                ),
              ),
            ]),
            if (ups.isNotEmpty)
              Positioned(
                left: 16,
                bottom: 16,
                child: _UploadPanel(tasks: ups, onClose: () => setState(() => _panelSince = DateTime.now())),
              ),
            if (_drag)
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.upload_file, size: 56), SizedBox(height: 8), Text('Drop to Upload Here')])),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.point, required this.segs, required this.onTap});
  final Point point;
  final List<String> segs;
  final void Function(int count) onTap;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
          for (var i = 0; i <= segs.length; i++) ...[
            if (i > 0) const Icon(Icons.chevron_right, size: 18),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: i == segs.length ? null : () => onTap(i),
              child: Text(i == 0 ? point.name : segs[i - 1]),
            ),
          ],
        ]),
      ),
      if (point.maxBytes > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            Expanded(child: UsageBar(used: point.usedBytes, max: point.maxBytes)),
            const SizedBox(width: 10),
            Text('${fmtBytes(point.usedBytes)} / ${fmtBytes(point.maxBytes)}', style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
    ]);
  }
}

/// Floating upload status card: overall state plus per-file progress.
class _UploadPanel extends StatelessWidget {
  const _UploadPanel({required this.tasks, required this.onClose});
  final List<TransferTask> tasks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final active = tasks.where((x) => x.active).length;
    final failed = tasks.where((x) => x.state == TState.failed).length;
    final done = tasks.where((x) => x.state == TState.done).length;
    final title = active > 0
        ? 'Uploading ${done + 1 > tasks.length ? tasks.length : done + 1} of ${tasks.length}…'
        : (failed > 0 ? '$failed Upload${failed == 1 ? '' : 's'} Failed' : 'Upload Complete');
    // Active first, then failed, then done.
    final sorted = [...tasks]..sort((a, b) => _rank(a).compareTo(_rank(b)));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
      child: Card(
        elevation: 6,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (active > 0)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
              else
                Icon(failed > 0 ? Icons.error_outline : Icons.check_circle, size: 20, color: failed > 0 ? cs.error : cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: t.titleSmall)),
              IconButton(tooltip: 'Dismiss', icon: const Icon(Icons.close, size: 18), onPressed: onClose),
            ]),
            for (final x in sorted.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
                    const SizedBox(width: 8),
                    Text(
                      switch (x.state) {
                        TState.done => 'Done',
                        TState.failed => 'Failed',
                        TState.canceled => 'Cancelled',
                        TState.queued => 'Waiting',
                        TState.running => x.fraction == null ? 'Uploading' : '${(x.fraction! * 100).round()}%',
                      },
                      style: t.labelSmall?.copyWith(color: x.state == TState.failed ? cs.error : cs.onSurfaceVariant),
                    ),
                  ]),
                  if (x.active) Padding(padding: const EdgeInsets.only(top: 3), child: LinearProgressIndicator(value: x.state == TState.running ? x.fraction : null, minHeight: 4)),
                  if (x.state == TState.failed && x.error != null) Text(x.error!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.error)),
                ]),
              ),
            if (sorted.length > 5)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('+ ${sorted.length - 5} more', style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
          ]),
        ),
      ),
    );
  }

  static int _rank(TransferTask t) => t.active ? 0 : (t.state == TState.failed ? 1 : 2);
}
