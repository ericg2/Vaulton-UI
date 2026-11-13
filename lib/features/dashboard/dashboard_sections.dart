import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../backups/backup_flow.dart';
import '../backups/job_detail_page.dart';
import '../backups/jobs_page.dart' show JobCard;
import '../files/files_page.dart';
import 'dashboard_data.dart';

/// Greeting and the one-line summary of what needs attention.
class DashboardGreeting extends ConsumerWidget {
  const DashboardGreeting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final points = ref.watch(dashboardPointsProvider);
    final jobs = ref.watch(dashboardJobsProvider).value;
    final health = ref.watch(dashboardHealthProvider).value;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hour = DateTime.now().hour;
    final greet = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');

    final failedPoints = points?.failedCount ?? 0;
    final failed = jobs?.failed ?? 0;
    final healthStatus = '${health?['status'] ?? ''}';
    final healthBad = healthStatus == 'Degraded' || healthStatus == 'Unhealthy';
    final attention = failedPoints > 0 || failed > 0 || healthBad;
    final message = failedPoints > 0
        ? '$failedPoints data folder${failedPoints == 1 ? '' : 's'} or backup vault${failedPoints == 1 ? '' : 's'} need attention.'
        : (failed > 0
            ? '$failed job${failed == 1 ? '' : 's'} failed in the last 24 hours.'
            : (healthBad ? 'System health is ${healthStatus.toLowerCase()}.' : 'Everything looks healthy.'));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$greet, ${user?.displayName ?? ''}', style: t.titleLarge),
        const SizedBox(height: 4),
        Row(children: [
          Icon(attention ? Icons.warning_amber_rounded : Icons.check_circle_outline, size: 16, color: attention ? cs.error : cs.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message,
              style: t.bodyMedium?.copyWith(color: attention ? cs.error : cs.onSurfaceVariant),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// The row of headline counters.
class DashboardStats extends ConsumerWidget {
  const DashboardStats({super.key, required this.onNavigate, required this.onShowHealth});

  /// Lets a tile jump to another section of the app.
  final void Function(String label) onNavigate;

  /// Scrolls to the health details.
  final VoidCallback onShowHealth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final canJobs = user?.has(Scopes.jobsManage) ?? false;
    final points = ref.watch(dashboardPointsProvider);
    final jobs = ref.watch(dashboardJobsProvider).value;
    final health = ref.watch(dashboardHealthProvider).value;
    final healthStatus = '${health?['status'] ?? ''}';
    final healthBad = healthStatus == 'Degraded' || healthStatus == 'Unhealthy';
    final failed = jobs?.failed ?? 0;

    final stats = <Widget>[
      _Stat(
        Icons.folder_outlined,
        points == null ? '—' : '${points.dataCount}',
        points != null && points.dataCount == 1 ? 'Data Folder' : 'Data Folders',
        () => onNavigate('Data Folders'),
      ),
      _Stat(
        Icons.inventory_2_outlined,
        points == null ? '—' : '${points.repoCount}',
        points != null && points.repoCount == 1 ? 'Backup Vault' : 'Backup Vaults',
        () => onNavigate('Backup Vaults'),
      ),
      if (canJobs)
        _Stat(
          Icons.sync,
          jobs == null ? '—' : '${jobs.active}',
          'Active Jobs',
          () => onNavigate('Activity'),
          highlight: (jobs?.running ?? 0) > 0,
        ),
      if (canJobs)
        _Stat(
          failed > 0 ? Icons.error_outline : Icons.check_circle_outline,
          jobs == null ? '—' : '$failed',
          'Failed Jobs (24h)',
          () => onNavigate('Activity'),
          bad: failed > 0,
        ),
      if (healthStatus.isNotEmpty)
        _Stat(
          healthBad ? Icons.warning_amber_rounded : Icons.health_and_safety_outlined,
          healthStatus,
          'System Health',
          onShowHealth,
          bad: healthStatus == 'Unhealthy',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(builder: (ctx, c) {
        final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 520 ? 2 : 1);
        final w = (c.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final s in stats) SizedBox(width: w, child: s),
        ]);
      }),
    );
  }
}

/// The checklist that walks a new account through the first steps.
class DashboardSetup extends ConsumerWidget {
  const DashboardSetup({super.key, required this.onNavigate});

  final void Function(String label) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final canJobs = user?.has(Scopes.jobsManage) ?? false;
    final canManageRoots = user?.has(Scopes.rootsManage) ?? false;
    final points = ref.watch(dashboardPointsProvider);
    final locations = ref.watch(dashboardHasLocationsProvider).value;
    final jobs = ref.watch(dashboardJobsProvider).value;
    if (points == null || locations == null) return const SizedBox.shrink();

    final lastBackup = jobs?.lastBackup;
    final hasLocations = locations;
    final hasDatas = points.dataCount > 0;
    final hasRepos = points.repoCount > 0;
    if (hasLocations && hasDatas && hasRepos && !(canJobs && lastBackup == null)) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rocket_launch_outlined, color: cs.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Finish Setting Up Vaulton',
                    style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SetupStep(
              title: 'Create a Location',
              subtitle: canManageRoots ? '' : 'Connect a cloud account or ask an administrator to allocate local storage.',
              complete: hasLocations,
              actionLabel: 'Set Up',
              onPressed: !hasLocations ? () => onNavigate('Locations') : null,
            ),
            _SetupStep(
              title: 'Create a Data Folder',
              subtitle: '',
              complete: hasDatas,
              actionLabel: 'Set Up',
              onPressed: hasLocations && !hasDatas ? () => onNavigate('Data Folders') : null,
            ),
            _SetupStep(
              title: 'Create a Backup Vault',
              subtitle: '',
              complete: hasRepos,
              actionLabel: 'Set Up',
              onPressed: hasLocations && !hasRepos ? () => onNavigate('Backup Vaults') : null,
            ),
            if (canJobs)
              _SetupStep(
                title: 'Run Your First Backup',
                subtitle: '',
                complete: lastBackup != null,
                actionLabel: 'Start',
                onPressed: hasDatas && hasRepos && lastBackup == null ? () => startBackup(context, ref) : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// Buttons that start the most common tasks.
class DashboardQuickActions extends ConsumerWidget {
  const DashboardQuickActions({super.key, required this.onNavigate});

  final void Function(String label) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canJobs = ref.watch(userProvider)?.has(Scopes.jobsManage) ?? false;
    return Section('Quick Actions', children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          if (canJobs) FilledButton.icon(onPressed: () => startBackup(context, ref), icon: const Icon(Icons.backup_outlined), label: const Text('Backup Now')),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FilesPage())),
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload'),
          ),
          OutlinedButton.icon(onPressed: () => onNavigate('Storage'), icon: const Icon(Icons.storage_outlined), label: const Text('Storage')),
        ]),
      ),
    ]);
  }
}

/// How much space the folders and vaults use.
class DashboardUsage extends ConsumerWidget {
  const DashboardUsage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(dashboardPointsProvider);
    final jobs = ref.watch(dashboardJobsProvider).value;
    if (points == null || points.maxBytes <= 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final lastOk = jobs?.lastBackup;
    final lastCheck = jobs?.lastCheck;

    return Section('Storage Usage', children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              UsageBar(used: points.usedBytes, max: points.maxBytes),
              const SizedBox(height: 8),
              Text('${fmtBytes(points.usedBytes)} used of ${fmtBytes(points.maxBytes)} allocated', style: t.bodySmall),
              if (lastOk != null) ...[
                const SizedBox(height: 4),
                Text('Last backup: ${fmtDate(lastOk.endDate ?? lastOk.startDate)}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
              if (lastCheck != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Icon(
                    lastCheck.phase == JobPhase.succeeded ? Icons.verified : Icons.report_problem_outlined,
                    size: 14,
                    color: lastCheck.phase == JobPhase.succeeded ? cs.primary : cs.error,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Last verification: ${fmtDate(lastCheck.endDate ?? lastCheck.startDate)}'
                      '${lastCheck.phase == JobPhase.succeeded ? ' · passed' : lastCheck.phase == JobPhase.failed ? ' · failed' : ''}',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// The server health checks, one row each.
class DashboardHealth extends ConsumerWidget {
  const DashboardHealth({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(dashboardHealthProvider).value;
    if (health == null) return const SizedBox.shrink();
    final checks = (health['checks'] as List? ?? const []).map(toJson).toList();
    if (checks.isEmpty) return const SizedBox.shrink();

    return Section('System Health', children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < checks.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _HealthRow(check: checks[i]),
            ],
          ]),
        ),
      ),
    ]);
  }
}

/// The most recent jobs.
class DashboardActivity extends ConsumerWidget {
  const DashboardActivity({super.key, required this.onNavigate});

  final void Function(String label) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canJobs = ref.watch(userProvider)?.has(Scopes.jobsManage) ?? false;
    if (!canJobs) return const SizedBox.shrink();
    final jobs = ref.watch(dashboardJobsProvider).value;
    final names = ref.watch(pointNamesProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final active = <RepoJob>[];
    final finished = <RepoJob>[];
    for (final j in jobs?.jobs ?? const <RepoJob>[]) {
      (j.active ? active : finished).add(j);
    }

    return Section('Activity', children: [
      for (final j in active)
        JobCard(
          job: j,
          names: names,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id))),
        ),
      if (active.isEmpty && finished.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text('No recent activity.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
      for (final j in finished.take(5))
        JobCard(
          job: j,
          names: names,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobDetailPage(jobId: j.id))),
        ),
      if (finished.length > 5)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => onNavigate('Activity'), child: const Text('View All')),
          ),
        ),
    ]);
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.title,
    required this.subtitle,
    required this.complete,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final bool complete;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: complete ? cs.primary : cs.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                    decoration: complete ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
          if (!complete && onPressed != null)
            TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.check});
  final Json check;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final status = '${check['status'] ?? 'Unknown'}';
    final healthy = status == 'Healthy';
    final degraded = status == 'Degraded';
    final color = healthy ? cs.primary : (degraded ? cs.tertiary : cs.error);
    final icon = healthy ? Icons.check_circle_outline : (degraded ? Icons.warning_amber_rounded : Icons.error_outline);
    final description = '${check['description'] ?? ''}'.trim();
    final disk = _diskSummary(check);
    final details = [if (description.isNotEmpty) description, ?disk].join('\n');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_healthName('${check['name'] ?? ''}'), style: t.titleSmall),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(details, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            constraints: const BoxConstraints(minWidth: 76, maxWidth: 104),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              status,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

String _healthName(String name) => switch (name) {
      'database' => 'Database',
      'storage-backend' => 'Storage Backend',
      'disk-space' => 'Disk Space',
      'smb' => 'SMB',
      _ => name.isEmpty ? 'Health Check' : name,
    };

/// Formats the per-path disk data attached by the API's disk health check.
String? _diskSummary(Json check) {
  if ('${check['name']}' != 'disk-space') return null;
  final data = check['data'];
  if (data is! Map) return null;

  final entries = <({String path, String text})>[];
  data.forEach((path, value) {
    if (value is! Map) return;
    final free = (value['freeBytes'] as num?)?.toInt();
    final total = (value['totalBytes'] as num?)?.toInt();
    if (free == null || total == null || total <= 0) return;
    final percent = ((value['freePercent'] as num?)?.toDouble() ?? free / total * 100).clamp(0, 100);
    entries.add((
      path: '$path',
      text: '${fmtBytes(free)} free of ${fmtBytes(total)} (${percent.toStringAsFixed(0)}% free)',
    ));
  });
  if (entries.isEmpty) return null;
  // A single volume does not need a path prefix; multiple volumes do.
  return entries
      .map((e) => entries.length == 1 ? e.text : '${e.path} — ${e.text}')
      .join('\n');
}

/// A single headline counter.
class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label, this.onTap, {this.highlight = false, this.bad = false});
  final IconData icon;
  final String value, label;
  final VoidCallback onTap;
  final bool highlight, bad;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = bad ? cs.errorContainer : (highlight ? cs.tertiaryContainer : cs.surfaceContainerHigh);
    final fg = bad ? cs.onErrorContainer : (highlight ? cs.onTertiaryContainer : cs.onSurface);
    return Card(
      margin: EdgeInsets.zero,
      color: bg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: fg, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: fg, height: 1.05, fontWeight: FontWeight.w600),
                ),
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg.withValues(alpha: 0.8))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
