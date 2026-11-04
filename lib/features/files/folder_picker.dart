import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';

class PickedFolder {
  PickedFolder(this.point, this.path);
  final Point point;
  final String path;
}

/// Lets the user choose any folder in any of their data folders.
Future<PickedFolder?> pickFolder(BuildContext context, {String? initialPointId, String title = 'Choose Destination', String? initialPath}) =>
    showDialog<PickedFolder>(context: context, builder: (_) => _FolderPickerDialog(initialPointId: initialPointId, title: title, initialPath: initialPath));

Future<List<Point>> loadAllPoints(WidgetRef ref) async {
  final v = ref.read(vaultonProvider);
  final out = <Point>[];
  String? cursor;
  do {
    final p = await v.datas(cursor: cursor, limit: 100);
    out.addAll(p.items);
    cursor = p.hasMore ? p.nextCursor : null;
  } while (cursor != null);
  return out;
}

class _FolderPickerDialog extends ConsumerStatefulWidget {
  const _FolderPickerDialog({this.initialPointId, required this.title, this.initialPath});
  final String? initialPointId, initialPath;
  final String title;
  @override
  ConsumerState<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<_FolderPickerDialog> {
  List<Point> _points = [];
  Point? _point;
  String _path = '/';
  List<Node>? _dirs;
  Object? _error;
  bool _loadingPoints = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath ?? '/';
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    setState(() {
      _loadingPoints = true;
      _error = null;
    });
    try {
      final points = await loadAllPoints(ref);
      if (!mounted) return;
      setState(() {
        _points = points.where((p) => !p.isEncrypted || p.isUnlocked).toList();
        _point = _points.where((x) => x.id == widget.initialPointId).firstOrNull ?? _points.firstOrNull;
        _loadingPoints = false;
        if (_point == null) _dirs = [];
      });
      _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loadingPoints = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final point = _point;
    if (point == null) return;
    final path = _path;
    final generation = ++_loadGeneration;
    setState(() {
      _dirs = null;
      _error = null;
    });
    try {
      final v = ref.read(vaultonProvider);
      final dirs = <Node>[];
      String? cursor;
      do {
        final page = await v.list(point.id, path, cursor: cursor, limit: 200);
        dirs.addAll(page.items.where((n) => n.isDir));
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
      if (mounted && generation == _loadGeneration) setState(() => _dirs = dirs);
    } catch (e) {
      if (mounted && generation == _loadGeneration) setState(() => _error = e);
    }
  }

  Future<void> _createFolder() async {
    final point = _point;
    final path = _path;
    if (point == null) return;
    final name = await promptText(
      context,
      'New Folder',
      'Folder name',
      ok: 'Create',
      intro: 'Create a folder inside the directory you are currently viewing.',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(vaultonProvider).mkdir(point.id, joinPath(path, name.trim()));
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogHeight = (MediaQuery.sizeOf(context).height - 200)
        .clamp(120.0, 420.0)
        .toDouble();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: dialogHeight,
        child: _loadingPoints
            ? const Center(child: CircularProgressIndicator())
            : _point == null && _error != null
                ? ErrorView(_error!, onRetry: _loadPoints)
                : _point == null
                    ? EmptyView(_points.isEmpty ? 'Unlock an encrypted Data Folder in Storage before choosing a sync destination.' : 'Create a data folder before choosing a location.', icon: Icons.folder_off_outlined)
                    : Column(children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _point?.id,
                  decoration: const InputDecoration(labelText: 'Data Folder'),
                  items: [for (final p in _points) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (id) {
                    final selected = _points.where((p) => p.id == id).firstOrNull;
                    if (selected == null) return;
                    setState(() {
                      _point = selected;
                      _path = '/';
                    });
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _path == '/' ? null : () {
                      _path = parentPath(_path);
                      _load();
                    },
                  ),
                  Expanded(child: Text(_path, overflow: TextOverflow.ellipsis)),
                ]),
                const Divider(height: 1),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _point == null ? null : _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('New Folder'),
                  ),
                ),
                Expanded(
                  child: _error != null
                      ? ErrorView(_error!, onRetry: _load)
                      : _dirs == null
                          ? const Center(child: CircularProgressIndicator())
                          : _dirs!.isEmpty
                              ? const EmptyView('No subfolders.', icon: Icons.folder_open)
                              : ListView(children: [
                                  for (final d in _dirs!)
                                    ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.folder),
                                      title: Text(d.name),
                                      onTap: () {
                                        _path = joinPath(_path, d.name);
                                        _load();
                                      },
                                    ),
                                ]),
                ),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _point == null ? null : () => Navigator.pop(context, PickedFolder(_point!, _path)),
          child: const Text('Select This Folder'),
        ),
      ],
    );
  }
}
