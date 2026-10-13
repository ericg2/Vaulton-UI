import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../background/background_api.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../../core/timezones.dart';
import '../../core/widgets.dart';
import '../../platform/desktop_window.dart';
import 'sync_models.dart';
import 'sync_service.dart';
import 'sync_source.dart';
import '../files/folder_picker.dart';

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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(title)),
            Transform.scale(
              scale: 0.82,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      );
}

/// A labelled path row (Source / Destination). Stacks the Browse button under the
/// text on narrow screens so nothing gets squeezed or cut off.
class _PathRow extends StatelessWidget {
  const _PathRow({required this.label, required this.value, required this.onBrowse});
  final String label;
  final String value;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 380;
      final text = Text(
        value,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
      final button = OutlinedButton.icon(
        onPressed: onBrowse,
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Browse'),
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: tt.titleSmall),
        const SizedBox(height: 4),
        if (narrow) ...[
          text,
          const SizedBox(height: 8),
          button,
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: text),
            const SizedBox(width: 10),
            button,
          ]),
      ]);
    });
  }
}

class _RootWarning extends StatelessWidget {
  const _RootWarning();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error, width: 1.2),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
          child: Icon(Icons.priority_high_rounded, size: 18, color: cs.onError),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Root Folder Selected',
              style: tt.titleSmall?.copyWith(color: cs.error, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'This syncs to the top level of the data folder. Existing files outside '
              'your source may be overwritten or deleted. Choose a subfolder unless you are sure.',
              style: tt.bodySmall?.copyWith(color: cs.onErrorContainer, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }
}

class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key, this.settingsSyncId});

  final String? settingsSyncId;
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
  final Set<String> _activeSyncIds = {};

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
        for (final p in profiles) {
          _status[p.id] = SyncRunStatus.load(prefs, p.id);
        }
      });
      await _openRequestedSettings(profiles);
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
      for (final p in _profiles) {
        _status[p.id] = SyncRunStatus.load(prefs, p.id);
      }
    });
  }

  Future<void> _openRequestedSettings(List<SyncProfile> profiles) async {
    final id = widget.settingsSyncId;
    if (id == null) return;
    final profile = profiles.where((p) => p.id == id).firstOrNull;
    if (profile == null || !mounted) return;
    final source = SyncSourceInfo(kind: profile.sourceKind, location: profile.sourceLocation, label: profile.sourceLabel);
    final updated = await _configure(profile, source);
    if (updated == null || !mounted) return;
    final i = _profiles.indexWhere((p) => p.id == profile.id);
    if (i < 0) return;
    _profiles[i] = updated;
    await SyncProfile.saveAll(ref.read(prefsProvider), _profiles);
    await configureSyncSchedules(_profiles);
    if (mounted) setState(() {});
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

  Future<SyncProfile?> _configure(SyncProfile? existing, SyncSourceInfo initialSource) async {
    var source = initialSource;
    var name = existing?.name ?? source.label;
    var pointId = existing?.pointId ?? _points.first.id;
    var remoteDir = existing?.remoteDir ?? '/${source.label}';
    final deviceTz = await deviceTimeZone();
    if (!mounted) return null;
    var cron = existing?.cron ?? '0 2 * * *';
    var timeZone = existing?.timeZone ?? deviceTz ?? 'UTC';
    var skipIfRunning = existing?.skipIfRunning ?? true;
    var enabled = existing?.enabled ?? true;
    var deleteExtras = existing?.deleteExtras ?? true;
    var wifiOnly = existing?.wifiOnly ?? true;
    var chargingOnly = existing?.chargingOnly ?? false;
    final nameCtl = TextEditingController(text: name);
    final cronCtl = TextEditingController(text: cron);

    final result = await showDialog<SyncProfile>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'New Sync' : 'Sync Settings'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
              const SizedBox(height: 10),
              _PathRow(
                label: 'Source',
                value: source.location,
                onBrowse: () async {
                  final picked = await pickSyncSource();
                  if (picked != null) set(() => source = picked);
                },
              ),
              const SizedBox(height: 14),
              _PathRow(
                label: 'Destination',
                value: _pointName(pointId) + remoteDir,
                onBrowse: () async {
                  final picked = await pickFolder(
                    ctx,
                    initialPointId: pointId,
                    initialPath: remoteDir,
                    title: 'Choose Destination',
                  );
                  if (picked != null) {
                    set(() {
                      pointId = picked.point.id;
                      remoteDir = picked.path;
                    });
                  }
                },
              ),
              if (remoteDir == '/') ...[
                const SizedBox(height: 12),
                const _RootWarning(),
              ],
              const SizedBox(height: 14),
              CronField(controller: cronCtl),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: timeZone,
                decoration: const InputDecoration(labelText: 'Time Zone'),
                items: [
                  for (final zone in timeZoneOptions(device: deviceTz, extra: existing?.timeZone))
                    DropdownMenuItem(value: zone, child: Text(zone)),
                ],
                onChanged: (v) {
                  if (v != null) set(() => timeZone = v);
                },
              ),
              const SizedBox(height: 12),
              _SettingSwitch(
                title: 'Skip if Already Running',
                value: skipIfRunning,
                onChanged: (v) => set(() => skipIfRunning = v),
              ),
              const SizedBox(height: 12),
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
                title: 'Match Destination to Source',
                value: deleteExtras,
                onChanged: (v) => set(() => deleteExtras = v),
              ),
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
              onPressed: () async {
                if (remoteDir.trim() == '/' && deleteExtras) {
                  final proceed = await showDialog<bool>(
                    context: ctx,
                    builder: (warningCtx) => AlertDialog(
                      title: const Text('Confirm Root Destination'),
                      content: const Text(
                        'Match destination to source is enabled for the Data Folder root. '
                        'Files outside the source may be permanently deleted.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(warningCtx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(warningCtx, true),
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
                  );
                  if (proceed != true) return;
                }
                final scheduleCron = cronCtl.text.trim();
                try {
                  final occurrences = await ref.read(vaultonProvider).previewCron(
                    scheduleCron,
                    tz: timeZone,
                    count: 1,
                  );
                  if (occurrences.isEmpty) throw StateError('No upcoming run could be calculated.');
                  Navigator.pop(ctx, SyncProfile(
                    id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.trim().isEmpty ? source.label : name.trim(),
                    sourceKind: source.kind,
                    sourceLocation: source.location,
                    sourceLabel: source.label,
                    pointId: pointId,
                    remoteDir: remoteDir.trim().isEmpty ? '/' : remoteDir.trim(),
                    enabled: enabled,
                    deleteExtras: deleteExtras,
                    intervalMinutes: existing?.intervalMinutes ?? 60,
                    cron: scheduleCron,
                    timeZone: timeZone,
                    skipIfRunning: skipIfRunning,
                    wifiOnly: wifiOnly,
                    chargingOnly: chargingOnly,
                    lastRun: existing?.lastRun ?? 0,
                    nextRun: occurrences.first.millisecondsSinceEpoch,
                  ));
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Invalid schedule: $e')),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtl.dispose();
    cronCtl.dispose();
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
      final error = e.toString();
      if (error.toLowerCase().contains('source folder is no longer available')) {
        p.enabled = false;
        final status = SyncRunStatus(
          phase: 'Failed',
          error: 'Source folder is unavailable.',
          message: 'Sync paused. Choose the source folder again to resume.',
          finishedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await status.save(ref.read(prefsProvider), p.id);
        await SyncProfile.saveAll(ref.read(prefsProvider), _profiles);
        await configureSyncSchedules(_profiles);
        if (mounted) setState(() => _status[p.id] = status);
      } else if (mounted) {
        toast(context, error, error: true);
      }
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
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  count.toString() + (bytes == '0 B' ? '' : ' · $bytes'),
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          );
        }
        return AlertDialog(
          title: const Text('Review Sync'),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          content: SizedBox(
            width: 560,
            child: ListView(shrinkWrap: true, children: [
              Text(
                '${p.sourceLabel} → ${_pointName(p.pointId)}${p.remoteDir}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
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
                'Source: ${s.scannedSource} items · Destination: ${s.scannedDestination} items',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (plan.changes.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    title: const Text('All Planned Changes'),
                    subtitle: Text('${plan.changes.length} items'),
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
                                    ? 'New file · ${fmtBytes(change.bytes)}'
                                    : change.kind == SyncChangeKind.update
                                        ? 'Update · ${fmtBytes(change.bytes)}'
                                        : change.kind == SyncChangeKind.mkdir
                                            ? 'Create folder'
                                            : 'Replace · ${fmtBytes(change.bytes)}',
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
                  child: Text('Nothing to sync. The destination folder will still be created.'),
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
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (plan.deletedFiles > 0) {
                    final ok = await confirm(
                      context,
                      'Remove Destination Extras?',
                      'This will permanently delete ${plan.deletedFiles} destination item${plan.deletedFiles == 1 ? '' : 's'} so the destination exactly matches the source.',
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
    if (!_activeSyncIds.add(p.id)) return;
    if (mounted) setState(() {});
    try {
      await _preview(p);
    } finally {
      _activeSyncIds.remove(p.id);
      if (mounted) setState(() {});
    }
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          content: SizedBox(
            width: 620,
            height: MediaQuery.sizeOf(ctx).height * 0.6,
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
                  'This permanently deletes ${selected.length} file${selected.length == 1 ? '' : 's'} from the source device. The Vaulton copies remain.',
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
                  toast(context, '$removed source file${removed == 1 ? '' : 's'} deleted');
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
        title: const Text('Sync'),
        actions: [
          if (desktop) IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: desktop ? 1180 : 720),
          child: ListView(
            padding: EdgeInsets.fromLTRB(desktop ? 12 : 0, 8, desktop ? 12 : 0, 24),
            children: [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(desktop ? 20 : 16),
                  child: LayoutBuilder(builder: (context, c) {
                    final narrow = c.maxWidth < 520;
                    final icon = Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.sync, color: cs.onPrimaryContainer, size: 24),
                    );
                    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Folder Sync', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Keep folders in sync automatically.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]);
                    final add = FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add Folder'));
                    if (narrow) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          icon,
                          const SizedBox(width: 16),
                          Expanded(child: text),
                        ]),
                        const SizedBox(height: 12),
                        SizedBox(width: double.infinity, child: add),
                      ]);
                    }
                    return Row(children: [
                      icon,
                      const SizedBox(width: 16),
                      Expanded(child: text),
                      const SizedBox(width: 12),
                      add,
                    ]);
                  }),
                ),
              ),
              if (active > 0)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 16),
                      Text('$active Sync${active == 1 ? '' : 's'} Running'),
                    ]),
                  ),
                ),
              if (_profiles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: EmptyView('No folders added', icon: Icons.sync),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.sync, color: p.enabled ? cs.primary : cs.outline),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${p.sourceLabel} → ${point?.name ?? 'Data Folder'}${p.remoteDir}',
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
          const SizedBox(height: 8),
          if (!p.enabled && st.message != null && st.error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: cs.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(st.error!, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onErrorContainer)),
                  const SizedBox(height: 2),
                  Text(st.message!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer)),
                ])),
              ]),
            ),
          if (running) ...[
            Padding(padding: const EdgeInsets.only(right: 8), child: Text(st.phase, style: Theme.of(context).textTheme.labelLarge)),
            if (st.current != null) Text(st.current!, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text(
              '${fmtBytes(st.bytesDone)} of ${fmtBytes(st.bytesTotal)} · ${st.completed} completed · ${st.failed} failed',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(p.cron + ' · ' + p.timeZone),
              _chip(p.deleteExtras ? 'Mirror' : 'Keep Extras'),
              if (p.nextRun > 0) _chip('Next Run: ${fmtDate(DateTime.fromMillisecondsSinceEpoch(p.nextRun))}'),
            ]),
            const SizedBox(height: 8),
            if (st.finishedAt > 0)
              Text(
                st.error ?? st.message ?? 'Last sync completed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: st.error == null ? cs.onSurfaceVariant : cs.error),
              ),
            if (plan != null && plan.changes.isNotEmpty)
              Text(
                '${plan.newFiles} new · ${plan.updatedFiles} updated · ${plan.deletedFiles} destination extras',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_safeCleanup[p.id]?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.cleaning_services_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(
                    '${_safeCleanup[p.id]!.length} source files are safe to delete',
                    style: Theme.of(context).textTheme.bodySmall,
                  )),
                  TextButton(onPressed: () => _reviewSourceCleanup(p), child: const Text('Review')),
                ]),
              ),
          ],
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.tonalIcon(
              onPressed: running || _activeSyncIds.contains(p.id) ? null : () => _run(p),
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final times = await guarded(
                  context,
                  () => ref.read(vaultonProvider).previewCron(p.cron, tz: p.timeZone, count: 5),
                );
                if (times == null || !mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Next Runs'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final time in times) Text(fmtDate(time))],
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                  ),
                );
              },
              child: const Text('Preview'),
            ),
            const SizedBox(width: 8),
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
            const Spacer(),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(p),
            ),
          ]),
        ]),
      ),
    );
  }

  String _frequencyLabel(int minutes) {
    if (minutes < 60) return 'Every $minutes minutes';
    if (minutes % 60 == 0) return 'Every ${minutes ~/ 60} hours';
    return 'Every $minutes minutes';
  }

  Widget _chip(String text) => chip(context, text);
}
