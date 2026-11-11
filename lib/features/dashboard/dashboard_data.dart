import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/scopes.dart';

/// Counts and byte totals for every data folder and backup vault.
class DashboardPoints {
  const DashboardPoints({
    required this.dataCount,
    required this.repoCount,
    required this.usedBytes,
    required this.maxBytes,
    required this.failedCount,
  });

  final int dataCount, repoCount, usedBytes, maxBytes, failedCount;
}

/// Recent jobs with the counts the dashboard shows next to them.
class DashboardJobs {
  const DashboardJobs({
    required this.jobs,
    required this.running,
    required this.waiting,
    required this.failed,
    this.lastBackup,
    this.lastCheck,
  });

  final List<RepoJob> jobs;
  final int running, waiting, failed;
  final RepoJob? lastBackup, lastCheck;

  /// Jobs that are running or waiting to run.
  int get active => running + waiting;

  /// Jobs that already finished.
  List<RepoJob> get finished => jobs.where((j) => !j.active).toList();
}

/// Totals for every data folder and backup vault.
///
/// Derived from the shared point list, so the dashboard never asks the server
/// for the same pages twice.
final dashboardPointsProvider = Provider<DashboardPoints?>((ref) {
  final points = ref.watch(allPointsProvider).value;
  if (points == null) return null;
  var used = 0, max = 0, failed = 0;
  for (final p in points.datas) {
    used += p.usedBytes;
    max += p.maxBytes;
    if (p.isError) failed++;
  }
  for (final p in points.repos) {
    used += p.usedBytes;
    max += p.maxBytes;
    if (p.isError) failed++;
  }
  return DashboardPoints(
    dataCount: points.datas.length,
    repoCount: points.repos.length,
    usedBytes: used,
    maxBytes: max,
    failedCount: failed,
  );
});

/// Recent jobs with the counts the dashboard shows.
final dashboardJobsProvider = FutureProvider<DashboardJobs>((ref) async {
  ref.watch(userProvider);
  if (!(ref.read(userProvider)?.has(Scopes.jobsManage) ?? false)) {
    return const DashboardJobs(jobs: [], running: 0, waiting: 0, failed: 0);
  }
  final v = ref.watch(vaultonProvider);
  final jobs = (await v.jobs(limit: 12)).items;
  final cutoff = DateTime.now().subtract(const Duration(hours: 24));
  var running = 0, waiting = 0, failed = 0;
  RepoJob? lastBackup, lastCheck;
  for (final j in jobs) {
    switch (j.phase) {
      case JobPhase.running:
        running++;
      case JobPhase.waiting:
        waiting++;
      case JobPhase.failed:
        if ((j.endDate ?? j.createdAt ?? cutoff).isAfter(cutoff)) failed++;
      case JobPhase.succeeded:
      case JobPhase.cancelled:
        break;
    }
    if (lastBackup == null && j.kind == 'backup' && j.phase == JobPhase.succeeded) lastBackup = j;
    if (lastCheck == null && j.kind == 'check') lastCheck = j;
  }
  return DashboardJobs(
    jobs: jobs,
    running: running,
    waiting: waiting,
    failed: failed,
    lastBackup: lastBackup,
    lastCheck: lastCheck,
  );
});

/// Whether the user has any storage location.
///
/// One row is enough to answer the question, so this asks for a single
/// location instead of the whole list.
final dashboardHasLocationsProvider = FutureProvider<bool>((ref) async {
  ref.watch(userProvider);
  final v = ref.watch(vaultonProvider);
  return (await v.roots(limit: 1)).items.isNotEmpty;
});

/// The server health report, or null when it cannot be read.
///
/// Health is informational, so a failed probe must not break the dashboard.
final dashboardHealthProvider = FutureProvider<Json?>((ref) async {
  ref.watch(userProvider);
  if (!(ref.read(userProvider)?.hasAny([Scopes.adminLogs, Scopes.adminSettings]) ?? false)) {
    return null;
  }
  final v = ref.watch(vaultonProvider);
  try {
    return await v.healthStatus();
  } catch (_) {
    return null;
  }
});
