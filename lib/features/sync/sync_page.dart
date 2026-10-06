import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../background/background_api.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import '../files/folder_picker.dart';
import '../transfers/transfer_manager.dart';
import 'folder_sync.dart';
import 'sync_api.dart';
import 'sync_models.dart';

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});
  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  late SyncSettings _s;
  late SyncStatus _st;
  List<FolderPair> _pairs = [];
  List<Point> _points = [];
  Timer? _poll;
  Timer? _folderPoll;
  final _remote = TextEditingController();

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(prefsProvider);
    _s = SyncSettings.load(prefs);
    _st = SyncStatus.load(prefs);
    _pairs = FolderPair.loadAll(prefs);
    _remote.text = _s.remoteDir;
    loadAllPoints(ref).then((p) {
      if (mounted) setState(() => _points = p);
    }).catchError((_) {});
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      await prefs.reload();
      if (mounted) setState(() => _st = SyncStatus.load(prefs));
    });
    _folderPoll = Timer.periodic(const Duration(seconds: 30), (_) => _runDuePairs());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _folderPoll?.cancel();
    _remote.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _s.save(ref.read(prefsProvider));
    await configurePhotoSync(_s);
    if (mounted) setState(() {});
  }

  Future<void> _setEnabled(bool v) async {
    if (v) {
      if (_s.pointId == null) {
        toast(context, 'Choose a destination data folder first', error: true);
        return;
      }
      if (!await requestPhotoPermission()) {
        if (mounted) toast(context, 'Photo access is required for backup. Allow it in system settings.', error: true);
        return;
      }
    }
    _s.enabled = v;
    await _save();
    if (v) await triggerPhotoSyncNow();
  }

  Future<void> _pickAlbums() async {
    final albums = await guarded(context, listAlbums);
    if (albums == null || !mounted) return;
    final chosen = {..._s.albumIds};
    final r = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Albums to Backup'),
          content: SizedBox(
            width: 400,
            child: ListView(shrinkWrap: true, children: [
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Select none to back up everything.')),
              for (final a in albums)
                CheckboxListTile(
                  title: Text(a.name),
                  subtitle: Text('${a.count} items'),
                  value: chosen.contains(a.id),
                  onChanged: (v) => set(() => v! ? chosen.add(a.id) : chosen.remove(a.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, chosen), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (r != null) {
      _s.albumIds = r.toList();
      await _save();
    }
  }

  Future<void> _addPair() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Folder to sync');
    if (dir == null || !mounted) return;
    final dest = await pickFolder(context, title: 'Upload into…');
    if (dest == null) return;
    _pairs.add(FolderPair(id: '${DateTime.now().millisecondsSinceEpoch}', localDir: dir, pointId: dest.point.id, remoteDir: dest.path));
    await FolderPair.saveAll(ref.read(prefsProvider), _pairs);
    setState(() {});
    await _runPair(_pairs.last);
  }

  Future<void> _runDuePairs() async {
    if (!isDesktop || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in [..._pairs]) {
      if (!p.enabled) continue;
      if (p.lastRun == 0 || now - p.lastRun >= p.intervalMinutes * 60000) await _runPair(p, quiet: true);
    }
  }

  Future<void> _runPair(FolderPair p, {bool quiet = false}) async {
    final prefs = ref.read(prefsProvider);
    final n = await guarded(context, () => runFolderPair(p, prefs, ref.read(transferProvider.notifier)));
    await FolderPair.saveAll(prefs, _pairs);
    if (mounted && !quiet && n != null) toast(context, n == 0 ? 'Folder is up to date' : 'Queued $n upload${n == 1 ? '' : 's'}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mobile = backgroundSupported;
    final desktop = isDesktop;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync & Backup')),
      body: ListView(children: [
        if (!mobile && !desktop)
          const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyView('Automatic sync needs the Android or desktop app.\nThe browser cannot read your files in the background.', icon: Icons.cloud_off_outlined),
          ),
        if (mobile) ...[
          Section('Photo & video backup', children: [
            Card(
              child: SwitchListTile(
                title: const Text('Back up photos and videos'),
                subtitle: Text(_s.enabled ? 'Runs in the background, even when the app is closed' : 'Off'),
                value: _s.enabled,
                onChanged: _setEnabled,
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  DropdownButtonFormField<String>(
                    initialValue: _points.any((p) => p.id == _s.pointId) ? _s.pointId : null,
                    decoration: const InputDecoration(labelText: 'Destination data folder'),
                    items: [for (final p in _points) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    onChanged: (v) {
                      _s.pointId = v;
                      _save();
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _remote,
                    decoration: const InputDecoration(labelText: 'Destination folder'),
                    onChanged: (v) {
                      _s.remoteDir = v.startsWith('/') ? v : '/$v';
                    },
                    onEditingComplete: _save,
                    onTapOutside: (_) => _save(),
                  ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Organise into year/month folders'), value: _s.organizeByDate, onChanged: (v) { _s.organizeByDate = v; _save(); }),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Include videos'), value: _s.includeVideos, onChanged: (v) { _s.includeVideos = v; _save(); }),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Wi‑Fi / unmetered only'), value: _s.wifiOnly, onChanged: (v) { _s.wifiOnly = v; _save(); }),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Only while charging'), value: _s.chargingOnly, onChanged: (v) { _s.chargingOnly = v; _save(); }),
                  DropdownButtonFormField<int>(
                    initialValue: const [15, 30, 60, 180, 360, 720, 1440].contains(_s.intervalMinutes) ? _s.intervalMinutes : 60,
                    decoration: const InputDecoration(labelText: 'Check for new photos every'),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 minutes')),
                      DropdownMenuItem(value: 30, child: Text('30 minutes')),
                      DropdownMenuItem(value: 60, child: Text('1 hour')),
                      DropdownMenuItem(value: 180, child: Text('3 hours')),
                      DropdownMenuItem(value: 360, child: Text('6 hours')),
                      DropdownMenuItem(value: 720, child: Text('12 hours')),
                      DropdownMenuItem(value: 1440, child: Text('Daily')),
                    ],
                    onChanged: (v) {
                      _s.intervalMinutes = v!;
                      _save();
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Albums'),
                    subtitle: Text(_s.albumIds.isEmpty ? 'Everything' : '${_s.albumIds.length} selected'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickAlbums,
                  ),
                ]),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(_st.isLive ? Icons.sync : Icons.check_circle_outline, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(_st.isLive ? 'Backing up…' : 'Idle', style: Theme.of(context).textTheme.titleSmall),
                  ]),
                  const SizedBox(height: 8),
                  if (_st.isLive) const LinearProgressIndicator(),
                  if (_st.current != null && _st.isLive) Text(_st.current!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${_st.totalSynced} items backed up in total'),
                  if (_st.uploaded > 0 || _st.skipped > 0 || _st.failed > 0)
                    Text('Last run: ${_st.uploaded} uploaded, ${_st.skipped} already there, ${_st.failed} failed'),
                  if (_st.lastRun > 0) Text('Last finished: ${fmtDate(DateTime.fromMillisecondsSinceEpoch(_st.lastRun))}'),
                  if (_st.error != null) Text(_st.error!, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.backup),
                      label: const Text('Backup now'),
                      onPressed: _s.pointId == null ? null : () async {
                        if (!await requestPhotoPermission()) {
                          if (context.mounted) toast(context, 'Photo access not granted', error: true);
                          return;
                        }
                        await triggerPhotoSyncNow();
                        if (context.mounted) toast(context, 'Backup started');
                      },
                    ),
                    TextButton(
                      onPressed: () async {
                        if (await confirm(context, 'Reset sync history?', 'Everything will be re-checked on the next run. Files already on the server are skipped, not duplicated.')) {
                          await resetSyncHistory(ref.read(prefsProvider));
                          setState(() => _st = SyncStatus.load(ref.read(prefsProvider)));
                        }
                      },
                      child: const Text('Reset history'),
                    ),
                  ]),
                ]),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Tip: for the most reliable background runs, exclude Vaulton from battery optimisation in Android settings. Backups resume where they left off.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ]),
        ],
        if (desktop)
          Section('Folder Sync', children: [
            if (_pairs.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Mirror local folders into a data folder. New and changed files are uploaded automatically while Vaulton is open or minimised.')),
            for (final p in _pairs)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.folder_special_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.localDir, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                          Text('→ ${_points.where((x) => x.id == p.pointId).firstOrNull?.name ?? 'Data Folder'}${p.remoteDir}',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline)),
                        ]),
                      ),
                      Switch(value: p.enabled, onChanged: (v) async {
                        p.enabled = v;
                        await FolderPair.saveAll(ref.read(prefsProvider), _pairs);
                        setState(() {});
                      }),
                    ]),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (ctx, c) {
                      final frequency = DropdownButton<int>(
                        value: const [5, 15, 30, 60, 180, 360].contains(p.intervalMinutes) ? p.intervalMinutes : 15,
                        onChanged: (v) async {
                          if (v == null) return;
                          p.intervalMinutes = v;
                          await FolderPair.saveAll(ref.read(prefsProvider), _pairs);
                          setState(() {});
                        },
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('Every 5 Minutes')),
                          DropdownMenuItem(value: 15, child: Text('Every 15 Minutes')),
                          DropdownMenuItem(value: 30, child: Text('Every 30 Minutes')),
                          DropdownMenuItem(value: 60, child: Text('Every Hour')),
                          DropdownMenuItem(value: 180, child: Text('Every 3 Hours')),
                          DropdownMenuItem(value: 360, child: Text('Every 6 Hours')),
                        ],
                      );
                      final last = p.lastRun == 0 ? 'Never' : fmtDate(DateTime.fromMillisecondsSinceEpoch(p.lastRun));
                      final controls = Wrap(spacing: 8, runSpacing: 8, children: [
                        frequency,
                        OutlinedButton.icon(onPressed: () => _runPair(p), icon: const Icon(Icons.sync, size: 18), label: const Text('Sync Now')),
                        IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: () async {
                          _pairs.remove(p);
                          await resetFolderState(ref.read(prefsProvider), p);
                          await FolderPair.saveAll(ref.read(prefsProvider), _pairs);
                          setState(() {});
                        }),
                      ]);
                      final meta = Text('Last Run: $last', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline));
                      return c.maxWidth < 620
                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [controls, const SizedBox(height: 6), meta])
                          : Row(children: [Expanded(child: meta), controls]);
                    }),
                  ]),
                ),
              ),
            Padding(padding: const EdgeInsets.all(12), child: Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(onPressed: _addPair, icon: const Icon(Icons.add), label: const Text('Add Folder')))),
          ]),
      ]),
    );
  }
}
