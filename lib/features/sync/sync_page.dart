import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../background/background_api.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import 'sync_models.dart';
import 'sync_service.dart';
import 'sync_source.dart';

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title)),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      );
}

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});
  @override ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  List<SyncProfile> _profiles = [];
  List<Point> _points = [];
  final Map<String, SyncRunStatus> _status = {};
  final Map<String, SyncPlan> _plans = {};
  final Map<String, List<SyncSourceEntry>> _safeCleanup = {};
  Timer? _poll;
  Timer? _desktopSchedule;
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshStatus());
    _desktopSchedule = Timer.periodic(const Duration(seconds: 30), (_) => _runDueDesktop());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _desktopSchedule?.cancel();
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = ref.read(prefsProvider);
    final profiles = SyncProfile.loadAll(prefs);
    try {
      final points = <Point>[];
      String? cursor;
      do {
        final page = await ref.read(vaultonProvider).datas(cursor: cursor, limit: 200);
        points.addAll(page.items);
        cursor = page.hasMore ? page.nextCursor : null;
      } while (cursor != null);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _points = points;
        for (final p in profiles) _status[p.id] = SyncRunStatus.load(prefs, p.id);
      });
    } catch (_) {
      if (mounted) setState(() => _profiles = profiles);
    }
  }

  Future<void> _refreshStatus() async {
    final prefs = ref.read(prefsProvider);
    await prefs.reload();
    if (!mounted) return;
    setState(() {
      _profiles = SyncProfile.loadAll(prefs);
      for (final p in _profiles) _status[p.id] = SyncRunStatus.load(prefs, p.id);
    });
  }

  Future<void> _add() async {
    if (_points.isEmpty) {
      toast(context, 'No data folders are available.', error: true);
      return;
    }
    final source = await pickSyncSource();
    if (source == null || !mounted) return;
    final cfg = await _configure(null, source);
    if (cfg == null) return;
    final prefs = ref.read(prefsProvider);
    _profiles = [..._profiles, cfg];
    await SyncProfile.saveAll(prefs, _profiles);
    await configureSyncSchedules(_profiles);
    await _load();
    await _preview(cfg);
  }

  Future<SyncProfile?> _configure(SyncProfile? existing, SyncSourceInfo source) async {
    var name = existing?.name ?? source.label;
    var pointId = existing?.pointId ?? _points.first.id;
    var remoteDir = existing?.remoteDir ?? '/' + source.label;
    var interval = existing?.intervalMinutes ?? 60;
    var enabled = existing?.enabled ?? true;
    var deleteExtras = existing?.deleteExtras ?? true;
    var wifiOnly = existing?.wifiOnly ?? true;
    var chargingOnly = existing?.chargingOnly ?? false;
    final nameCtl = TextEditingController(text: name);
    final remoteCtl = TextEditingController(text: remoteDir);

    final result = await showDialog<SyncProfile>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'New Sync' : 'Sync Settings'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Sync Name'),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Source'),
                subtitle: Text(source.label, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              DropdownButtonFormField<String>(
                initialValue: pointId,
                decoration: const InputDecoration(labelText: 'Destination Data Folder'),
                items: [for (final p in _points) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => set(() => pointId = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remoteCtl,
                decoration: const InputDecoration(labelText: 'Destination Folder'),
                onChanged: (v) => remoteDir = v.startsWith('/') ? v : '/' + v,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mirror Exactly'),
                          SizedBox(height: 2),
                          Text(
                            'Match destination to source.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: deleteExtras,
                      onChanged: (v) => set(() => deleteExtras = v),
                    ),
                  ],
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: interval,
                decoration: const InputDecoration(labelText: 'Sync Frequency'),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('Every 15 Minutes')),
                  DropdownMenuItem(value: 30, child: Text('Every 30 Minutes')),
                  DropdownMenuItem(value: 60, child: Text('Every Hour')),
                  DropdownMenuItem(value: 180, child: Text('Every 3 Hours')),
                  DropdownMenuItem(value: 360, child: Text('Every 6 Hours')),
                  DropdownMenuItem(value: 720, child: Text('Every 12 Hours')),
                  DropdownMenuItem(value: 1440, child: Text('Daily')),
                ],
                onChanged: (v) => set(() => interval = v!),
              ),
              if (backgroundSupported) ...[
                _SettingSwitch(
                  title: 'Wi-Fi / Unmetered Only',
                  value: wifiOnly,
                  onChanged: (v) => set(() => wifiOnly = v),
                ),
                _SettingSwitch(
                  title: 'Only While Charging',
                  value: chargingOnly,
                  onChanged: (v) => set(() => chargingOnly = v),
                ),
              ],
              _SettingSwitch(
                title: 'Enabled',
                value: enabled,
                onChanged: (v) => set(() => enabled = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, SyncProfile(
                id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                name: name.trim().isEmpty ? source.label : name.trim(),
                sourceKind: source.kind,
                sourceLocation: source.location,
                sourceLabel: source.label,
                pointId: pointId,
                remoteDir: remoteDir.trim().isEmpty ? '/' : remoteDir.trim(),
                enabled: enabled,
                deleteExtras: deleteExtras,
                intervalMinutes: interval,
                wifiOnly: wifiOnly,
                chargingOnly: chargingOnly,
                lastRun: existing?.lastRun ?? 0,
                nextRun: existing?.nextRun ?? (DateTime.now().millisecondsSinceEpoch + interval * 60000),
              )),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtl.dispose();
    remoteCtl.dispose();
    return result;
  }

  Future<void> _runDueDesktop() async {
    if (!isDesktop || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in [..._profiles]) {
      if (!p.enabled || _status[p.id]?.running == true) continue;
      if (p.nextRun > 0 && now < p.nextRun) continue;
      try {
        await runScheduledSync(
          ref.read(apiClientProvider),
          ref.read(prefsProvider),
          p,
        );
      } catch (_) {}
    }
    await _refreshStatus();
  }

  Future<void> _preview(SyncProfile p) async {
    try {
      final plan = await buildSyncPlan(
        ref.read(apiClientProvider),
        p,
        ref.read(prefsProvider),
        onProgress: (s) {
          if (mounted) setState(() => _status[p.id] = s);
        },
      );
      if (!mounted) return;
      setState(() => _plans[p.id] = plan);
      await _showPlan(p, plan);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _apply(SyncProfile p, SyncPlan plan) async {
    _cancel = CancelToken();
    try {
      await applySyncPlan(
        ref.read(apiClientProvider),
        p,
        plan,
        ref.read(prefsProvider),
        onProgress: (s) {
          if (mounted) setState(() => _status[p.id] = s);
        },
        cancel: _cancel,
      );
      p.lastRun = DateTime.now().millisecondsSinceEpoch;
      p.nextRun = p.lastRun + p.intervalMinutes * 60000;
      await SyncProfile.saveAll(ref.read(prefsProvider), _profiles);
      await configureSyncSchedules(_profiles);
      if (mounted) toast(context, 'Sync complete');
      final source = openSyncSource(SyncSourceInfo(kind: p.sourceKind, location: p.sourceLocation, label: p.sourceLabel));
      final safe = (await source.scan()).where((x) => !x.isDir).toList();
      if (mounted) setState(() => _safeCleanup[p.id] = safe);
      await _refreshStatus();
    } catch (e) {
      if (mounted) toast(context, e is DioException && CancelToken.isCancel(e) ? 'Sync cancelled' : e.toString(), error: true);
    } finally {
      _cancel = null;
    }
  }

  Future<void> _showPlan(SyncProfile p, SyncPlan plan) async {
    if (!mounted) return;
    final s = _status[p.id] ?? SyncRunStatus();
    await showDialog(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget tile(IconData icon, String title, int count, String bytes, {bool danger = false}) {
          return Card(
            child: ListTile(
              leading: Icon(icon, color: danger ? cs.error : null),
              title: Text(title),
              trailing: Text(count.toString() + (bytes == '0 B' ? '' : ' · ' + bytes)),
            ),
          );
        }
        return AlertDialog(
          title: const Text('Review Sync'),
          content: SizedBox(
            width: 560,
            child: ListView(shrinkWrap: true, children: [
              Text(
                p.sourceLabel + ' → ' + _pointName(p.pointId) + p.remoteDir,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              tile(Icons.add_circle_outline, 'New Files', plan.newFiles,
                  fmtBytes(plan.uploads.where((x) => x.kind == SyncChangeKind.add).fold(0, (a, x) => a + x.bytes))),
              tile(Icons.sync, 'Updated Files', plan.updatedFiles,
                  fmtBytes(plan.uploads.where((x) => x.kind != SyncChangeKind.add).fold(0, (a, x) => a + x.bytes))),
              tile(Icons.delete_outline, 'Destination Extras', plan.deletedFiles,
                  fmtBytes(plan.deleteBytes), danger: plan.deletedFiles > 0),
              tile(Icons.check_circle_outline, 'Already In Sync', s.unchangedFiles, '0 B'),
              const SizedBox(height: 12),
              Text(
                'Source: ' + s.scannedSource.toString() + ' items · Destination: ' + s.scannedDestination.toString() + ' items',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (plan.changes.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    title: const Text('All Planned Changes'),
                    subtitle: Text(plan.changes.length.toString() + ' items'),
                    children: [
                      for (final change in plan.changes.take(500))
                        ListTile(
                          dense: true,
                          leading: Icon(
                            change.kind == SyncChangeKind.delete
                                ? Icons.delete_outline
                                : change.kind == SyncChangeKind.add
                                    ? Icons.add_circle_outline
                                    : change.kind == SyncChangeKind.mkdir
                                        ? Icons.create_new_folder_outlined
                                        : Icons.sync,
                            color: change.kind == SyncChangeKind.delete ? cs.error : null,
                          ),
                          title: Text(change.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            change.kind == SyncChangeKind.delete
                                ? 'Delete from destination'
                                : change.kind == SyncChangeKind.add
                                    ? 'New file · ' + fmtBytes(change.bytes)
                                    : change.kind == SyncChangeKind.update
                                        ? 'Update · ' + fmtBytes(change.bytes)
                                        : change.kind == SyncChangeKind.mkdir
                                            ? 'Create folder'
                                            : 'Replace · ' + fmtBytes(change.bytes),
                          ),
                        ),
                      if (plan.changes.length > 500)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Showing the first 500 changes.'),
                        ),
                    ],
                  ),
                ),
              if (plan.changes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Everything already matches.'),
                ),
              if (plan.deletedFiles > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Mirror Exactly is enabled. Destination extras will be permanently removed.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            if (plan.changes.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (plan.deletedFiles > 0) {
                    final ok = await confirm(
                      context,
                      'Remove Destination Extras?',
                      'This will permanently delete ' +
                          plan.deletedFiles.toString() +
                          ' destination item' +
                          (plan.deletedFiles == 1 ? '' : 's') +
                          ' so the destination exactly matches the source.',
                    );
                    if (!ok) return;
                  }
                  await _apply(p, plan);
                },
                child: Text(plan.deletedFiles > 0 ? 'Sync & Delete Extras' : 'Start Sync'),
              ),
          ],
        );
      },
    );
  }

  String _pointName(String id) => _points.where((p) => p.id == id).firstOrNull?.name ?? 'Data Folder';

  Future<void> _run(SyncProfile p) async {
    await _preview(p);
  }

  Future<void> _reviewSourceCleanup(SyncProfile p) async {
    final source = openSyncSource(SyncSourceInfo(kind: p.sourceKind, location: p.sourceLocation, label: p.sourceLabel));
    var files = List<SyncSourceEntry>.from(_safeCleanup[p.id] ?? const []);
    if (files.isEmpty) {
      try { files = (await source.scan()).where((x) => !x.isDir).toList(); } catch (_) {}
    }
    if (!mounted || files.isEmpty) {
      if (mounted) toast(context, 'There are no source files ready to remove.');
      return;
    }
    final selected = <String>{};
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Safe to Delete'),
          content: SizedBox(
            width: 620,
            height: 520,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'These files were successfully mirrored to Vaulton. Nothing is deleted until you choose the files and confirm.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (_, i) {
                    final f = files[i];
                    final checked = selected.contains(f.location);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) => set(() => v == true ? selected.add(f.location) : selected.remove(f.location)),
                      title: Text(f.relative, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(fmtBytes(f.size)),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            TextButton(
              onPressed: selected.isEmpty ? null : () async {
                Navigator.pop(ctx);
                final ok = await confirm(
                  context,
                  'Delete Source Files?',
                  'This permanently deletes ' + selected.length.toString() + ' file' + (selected.length == 1 ? '' : 's') + ' from the source device. The Vaulton copies remain.',
                );
                if (!ok) return;
                var removed = 0;
                for (final f in files.where((x) => selected.contains(x.location))) {
                  try {
                    await source.delete(f);
                    removed++;
                  } catch (_) {}
                }
                _safeCleanup[p.id] = files.where((x) => !selected.contains(x.location)).toList();
                if (mounted) {
                  setState(() {});
                  toast(context, removed.toString() + ' source file' + (removed == 1 ? '' : 's') + ' deleted');
                }
              },
              child: const Text('Delete Selected'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(SyncProfile p) async {
    if (!await confirm(context, 'Remove Sync?', 'This removes the sync configuration. Destination files are left untouched.')) return;
    _profiles.remove(p);
    await SyncProfile.saveAll(ref.read(prefsProvider), _profiles);
    await configureSyncSchedules(_profiles);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop;
    final cs = Theme.of(context).colorScheme;
    final active = _profiles.where((p) => _status[p.id]?.running == true).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync & Backup'),
        actions: [
          if (desktop) IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktop ? 1180 : 720),
          child: ListView(
            padding: EdgeInsets.fromLTRB(desktop ? 28 : 16, 16, desktop ? 28 : 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
                      child: Icon(Icons.sync, color: cs.onPrimaryContainer, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Keep Folders in Sync', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        const Text('Automatically sync folders, and keep your data up-to-date.'),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add Sync')),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              if (active > 0)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text(active.toString() + ' Sync' + (active == 1 ? '' : 's') + ' Running'),
                    ]),
                  ),
                ),
              if (_profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: EmptyView('No syncs yet. Add a source folder to get started.', icon: Icons.sync),
                  ),
                ),
              for (final p in _profiles) _profileCard(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard(SyncProfile p) {
    final cs = Theme.of(context).colorScheme;
    final st = _status[p.id] ?? SyncRunStatus();
    final point = _points.where((x) => x.id == p.pointId).firstOrNull;
    final plan = _plans[p.id];
    final running = st.running;
    final progress = st.bytesTotal > 0 ? (st.bytesDone / st.bytesTotal).clamp(0, 1).toDouble() : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.sync, color: p.enabled ? cs.primary : cs.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  p.sourceLabel + ' → ' + (point?.name ?? 'Data Folder') + p.remoteDir,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ]),
            ),
            Switch(
              value: p.enabled,
              onChanged: (v) async {
                p.enabled = v;
                await SyncProfile.saveAll(ref.read(prefsProvider), _profiles);
                await configureSyncSchedules(_profiles);
                setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 12),
          if (running) ...[
            Text(st.phase, style: Theme.of(context).textTheme.labelLarge),
            if (st.current != null) Text(st.current!, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(fmtBytes(st.bytesDone) + ' of ' + fmtBytes(st.bytesTotal) + ' · ' + st.completed.toString() + ' completed · ' + st.failed.toString() + ' failed'),
          ] else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(_frequencyLabel(p.intervalMinutes)),
              _chip(p.deleteExtras ? 'Mirror Exactly' : 'Keep Destination Extras'),
              if (p.nextRun > 0) _chip('Next Run ' + fmtDate(DateTime.fromMillisecondsSinceEpoch(p.nextRun))),
            ]),
            const SizedBox(height: 8),
            if (st.finishedAt > 0)
              Text(
                st.error ?? st.message ?? 'Last sync completed.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: st.error == null ? cs.onSurfaceVariant : cs.error),
              ),
            if (plan != null && plan.changes.isNotEmpty)
              Text(
                plan.newFiles.toString() + ' new · ' + plan.updatedFiles.toString() + ' updated · ' + plan.deletedFiles.toString() + ' destination extras',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_safeCleanup[p.id]?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.cleaning_services_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _safeCleanup[p.id]!.length.toString() + ' source files are safe to delete',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  TextButton(onPressed: () => _reviewSourceCleanup(p), child: const Text('Review')),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: running ? null : () => _run(p),
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
            ),
            OutlinedButton(
              onPressed: () async {
                final source = SyncSourceInfo(kind: p.sourceKind, location: p.sourceLocation, label: p.sourceLabel);
                final updated = await _configure(p, source);
                if (updated == null) return;
                final i = _profiles.indexWhere((x) => x.id == p.id);
                if (i < 0) return;
                _profiles[i] = updated;
                await SyncProfile.saveAll(ref.read(prefsProvider), _profiles);
                await configureSyncSchedules(_profiles);
                if (mounted) setState(() {});
              },
              child: const Text('Settings'),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Remove Sync',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(p),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  String _frequencyLabel(int minutes) {
    if (minutes < 60) return 'Every ' + minutes.toString() + ' Minutes';
    if (minutes % 60 == 0) return 'Every ' + (minutes ~/ 60).toString() + ' Hours';
    return 'Every ' + minutes.toString() + ' Minutes';
  }

  Widget _chip(String text) => Chip(label: Text(text), visualDensity: VisualDensity.compact);
}
