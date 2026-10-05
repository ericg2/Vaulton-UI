import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/timezones.dart';
import '../../core/util.dart';
import 'backup_options.dart';

Map<String, int> _policyOf(Schedule s) {
  final p = toJson(s.options['policy']);
  return {for (final e in p.entries) e.key: int.tryParse('${e.value}') ?? 0};
}

/// Shows whether this backup vault cleans up old snapshots automatically,
/// and lets you set that up. Cleanup is a recurring schedule on the server.
class CleanupCard extends ConsumerStatefulWidget {
  const CleanupCard({super.key, required this.repoId, required this.onRunNow});
  final String repoId;

  /// Opens the one-time cleanup sheet.
  final VoidCallback onRunNow;
  @override
  ConsumerState<CleanupCard> createState() => CleanupCardState();
}

class CleanupCardState extends ConsumerState<CleanupCard> {
  Schedule? _schedule;
  bool _loaded = false, _failed = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final page = await ref.read(vaultonProvider).schedules(repoId: widget.repoId, limit: 200);
      if (!mounted) return;
      setState(() {
        _schedule = page.items.where((s) => s.mode == 'retention').firstOrNull;
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _setUp() async {
    final existing = _schedule;
    final req = await showRetentionSheet(context, forSchedule: true, initial: existing == null ? null : toJson(existing.options['policy']));
    if (req == null || !mounted) return;
    final options = {'mode': 'retention', 'policy': req.policy, 'dryRun': false};
    final v = ref.read(vaultonProvider);
    if (existing != null) {
      await guarded(context, () => v.patchSchedule(existing.id, {'options': options}));
    } else {
      final tz = await deviceTimeZone();
      if (!mounted) return;
      final f = await formDialog(context, 'When should cleanup run?', [
        const FieldSpec('cron', 'Schedule', kind: 'cron', initial: '0 4 * * 0'),
        FieldSpec('tz', 'Time zone', kind: 'choice', options: timeZoneOptions(device: tz), initial: tz ?? 'UTC'),
      ], ok: 'Turn on cleanup', intro: 'Pick a time after your backups usually finish. Weekly is plenty for most people.');
      if (f == null || !mounted) return;
      await guarded(context, () => v.createSchedule({
            'name': 'Snapshot cleanup',
            'repoId': widget.repoId,
            'options': options,
            'cron': f['cron'],
            'timeZone': f['tz'],
            'enabled': true,
            'skipIfRunning': true,
          }));
    }
    await reload();
    if (mounted) toast(context, 'Automatic cleanup is on');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _failed) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final s = _schedule;
    final on = s != null && s.enabled;
    final fg = on ? cs.onSurface : cs.onTertiaryContainer;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Card(
          color: on ? null : cs.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(on ? Icons.auto_delete_outlined : Icons.warning_amber_rounded, color: on ? cs.primary : cs.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(on ? 'Automatic cleanup is on' : (s == null ? 'Old snapshots aren’t being cleaned up' : 'Automatic cleanup is paused'), style: t.titleSmall?.copyWith(color: fg))),
              ]),
              const SizedBox(height: 6),
              Text(
                on
                    ? '${describeRetention(_policyOf(s))}\nNext run: ${fmtDate(s.nextRunAt)}'
                    : 'Every backup adds a snapshot, so this vault will keep growing until it’s full. Turn on automatic cleanup to keep only the snapshots you need.',
                style: t.bodyMedium?.copyWith(color: fg),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 600;
                  final setupLabel = on ? 'Change plan' : (s == null ? 'Turn on cleanup' : 'Review plan');
                  final buttons = [
                    FilledButton.icon(onPressed: _setUp, icon: Icon(on ? Icons.edit_outlined : Icons.auto_delete_outlined), label: Text(setupLabel))
                  ];
                  if (!narrow) return Wrap(spacing: 8, runSpacing: 8, children: buttons);
                  return Row(children: [
                    Expanded(child: buttons[0]),
                  ]);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
