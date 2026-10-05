import 'package:flutter/material.dart';
import '../../core/models.dart';

class PhaseStyle {
  const PhaseStyle(this.bg, this.fg, this.icon, this.label);
  final Color bg, fg;
  final IconData icon;
  final String label;
}

PhaseStyle phaseStyle(BuildContext c, JobPhase p) {
  final cs = Theme.of(c).colorScheme;
  return switch (p) {
    JobPhase.succeeded => PhaseStyle(cs.primaryContainer, cs.onPrimaryContainer, Icons.check_circle_outline, 'Succeeded'),
    JobPhase.failed => PhaseStyle(cs.errorContainer, cs.onErrorContainer, Icons.error_outline, 'Failed'),
    JobPhase.running => PhaseStyle(cs.tertiaryContainer, cs.onTertiaryContainer, Icons.sync, 'Running'),
    JobPhase.cancelled => PhaseStyle(cs.surfaceContainerHighest, cs.onSurfaceVariant, Icons.block, 'Cancelled'),
    JobPhase.waiting => PhaseStyle(cs.secondaryContainer, cs.onSecondaryContainer, Icons.schedule, 'Waiting'),
  };
}

IconData kindIcon(String kind) => switch (kind) {
      'backup' => Icons.backup_outlined,
      'restore' => Icons.settings_backup_restore,
      'check' => Icons.fact_check_outlined,
      'forget' => Icons.delete_sweep_outlined,
      'retention' => Icons.auto_delete_outlined,
      _ => Icons.work_outline,
    };

String kindLabel(String kind) => switch (kind) {
      'backup' => 'Backup',
      'restore' => 'Restore',
      'check' => 'Start Check',
      'forget' => 'Delete snapshots',
      'retention' => 'View Retention',
      _ => kind.isEmpty ? 'Job' : '${kind[0].toUpperCase()}${kind.substring(1)}',
    };

String shortId(String s) => s.length > 8 ? s.substring(0, 8) : s;

/// One-line, human description of what the job does.
String jobSummary(RepoJob j) {
  final o = j.options;
  switch (j.kind) {
    case 'backup':
      return '${o['path'] ?? '/'}${o['dryRun'] == true ? ' (dry run)' : ''}';
    case 'restore':
      return '${shortId('${o['snapshotId'] ?? ''}')}:${o['snapshotPath'] ?? '/'} → ${o['outputPath'] ?? ''}${o['dryRun'] == true ? ' (dry run)' : ''}';
    case 'forget':
      final n = (o['snapshots'] as List?)?.length ?? 0;
      return '$n snapshot${n == 1 ? '' : 's'}';
    case 'retention':
      return o['dryRun'] == true ? 'Dry run' : 'Apply retention policy';
    default:
      return '';
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.phase, {super.key});
  final JobPhase phase;
  @override
  Widget build(BuildContext context) {
    final st = phaseStyle(context, phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(st.icon, size: 14, color: st.fg),
        const SizedBox(width: 4),
        Text(st.label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: st.fg)),
      ]),
    );
  }
}
