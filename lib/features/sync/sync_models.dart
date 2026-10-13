import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const kSyncProfiles = 'sync_profiles_v2';
const kSyncRunPrefix = 'sync_run_v2_';
const kSyncManifestPrefix = 'sync_manifest_v1_';

class SyncProfile {
  SyncProfile({
    required this.id, required this.name, required this.sourceKind, required this.sourceLocation,
    required this.sourceLabel, required this.pointId, required this.remoteDir,
    this.enabled = true, this.deleteExtras = true, this.intervalMinutes = 60,
    this.cron = '0 * * * *', this.timeZone = 'UTC', this.skipIfRunning = true,
    this.wifiOnly = true, this.chargingOnly = false, this.lastRun = 0, this.nextRun = 0,
  });
  final String id, name, sourceKind, sourceLocation, sourceLabel, pointId, remoteDir;
  bool enabled, deleteExtras, wifiOnly, chargingOnly, skipIfRunning;
  int intervalMinutes, lastRun, nextRun;
  String cron, timeZone;

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'sourceKind': sourceKind, 'sourceLocation': sourceLocation,
    'sourceLabel': sourceLabel, 'pointId': pointId, 'remoteDir': remoteDir,
    'enabled': enabled, 'deleteExtras': deleteExtras, 'intervalMinutes': intervalMinutes,
    'cron': cron, 'timeZone': timeZone, 'skipIfRunning': skipIfRunning,
    'wifiOnly': wifiOnly, 'chargingOnly': chargingOnly, 'lastRun': lastRun, 'nextRun': nextRun,
  };

  factory SyncProfile.fromJson(Map<String, dynamic> j) => SyncProfile(
    id: '${j['id']}', name: '${j['name'] ?? 'Folder Sync'}',
    sourceKind: '${j['sourceKind'] ?? 'path'}', sourceLocation: '${j['sourceLocation'] ?? ''}',
    sourceLabel: '${j['sourceLabel'] ?? j['sourceLocation'] ?? 'Source Folder'}',
    pointId: '${j['pointId']}', remoteDir: '${j['remoteDir'] ?? '/'}',
    enabled: j['enabled'] ?? true, deleteExtras: j['deleteExtras'] ?? true,
    intervalMinutes: j['intervalMinutes'] ?? 60,
    cron: j['cron'] ?? _legacySyncCron(j['intervalMinutes'] ?? 60),
    timeZone: j['timeZone'] ?? 'UTC', skipIfRunning: j['skipIfRunning'] ?? true,
    wifiOnly: j['wifiOnly'] ?? true, chargingOnly: j['chargingOnly'] ?? false,
    lastRun: j['lastRun'] ?? 0, nextRun: j['nextRun'] ?? 0,
  );

  static List<SyncProfile> loadAll(SharedPreferences p) {
    final raw = p.getString(kSyncProfiles);
    if (raw == null) return [];
    try { return [for (final j in jsonDecode(raw) as List) SyncProfile.fromJson(Map<String, dynamic>.from(j))]; }
    catch (_) { return []; }
  }

  static Future<void> saveAll(SharedPreferences p, List<SyncProfile> profiles) =>
      p.setString(kSyncProfiles, jsonEncode([for (final x in profiles) x.toJson()]));
}

String _legacySyncCron(int minutes) {
  if (minutes <= 30) return '*/' + minutes.toString() + ' * * * *';
  if (minutes < 1440) return '0 */' + (minutes / 60).round().toString() + ' * * *';
  return '0 2 * * *';
}

class SyncManifestEntry {
  const SyncManifestEntry({required this.size, required this.modified, this.hash});
  final int size;
  final int modified;
  final String? hash;

  Map<String, dynamic> toJson() => {
    'size': size,
    'modified': modified,
    if (hash != null) 'hash': hash,
  };

  factory SyncManifestEntry.fromJson(Map<String, dynamic> j) => SyncManifestEntry(
    size: j['size'] ?? 0,
    modified: j['modified'] ?? 0,
    hash: j['hash'] as String?,
  );
}

Map<String, SyncManifestEntry> loadSyncManifest(SharedPreferences p, String id) {
  final raw = p.getString('$kSyncManifestPrefix$id');
  if (raw == null) return {};
  try {
    final data = Map<String, dynamic>.from(jsonDecode(raw));
    return {
      for (final e in data.entries)
        e.key: SyncManifestEntry.fromJson(Map<String, dynamic>.from(e.value)),
    };
  } catch (_) {
    return {};
  }
}

Future<void> saveSyncManifest(
  SharedPreferences p,
  String id,
  Map<String, SyncManifestEntry> manifest,
) => p.setString(
  '$kSyncManifestPrefix$id',
  jsonEncode({for (final e in manifest.entries) e.key: e.value.toJson()}),
);

class SyncRunStatus {
  SyncRunStatus({
    this.running = false, this.phase = 'Idle', this.current, this.scannedSource = 0,
    this.scannedDestination = 0, this.totalFiles = 0, this.totalBytes = 0, this.newFiles = 0,
    this.updatedFiles = 0, this.deletedFiles = 0, this.unchangedFiles = 0, this.completed = 0,
    this.failed = 0, this.bytesDone = 0, this.bytesTotal = 0, this.startedAt = 0,
    this.finishedAt = 0, this.error, this.message,
  });
  bool running;
  String phase;
  String? current, error, message;
  int scannedSource, scannedDestination, totalFiles, totalBytes, newFiles, updatedFiles, deletedFiles;
  int unchangedFiles, completed, failed, bytesDone, bytesTotal, startedAt, finishedAt;

  Map<String, dynamic> toJson() => {
    'running': running, 'phase': phase, 'current': current, 'error': error, 'message': message,
    'scannedSource': scannedSource, 'scannedDestination': scannedDestination,
    'totalFiles': totalFiles, 'totalBytes': totalBytes, 'newFiles': newFiles,
    'updatedFiles': updatedFiles, 'deletedFiles': deletedFiles, 'unchangedFiles': unchangedFiles,
    'completed': completed, 'failed': failed, 'bytesDone': bytesDone, 'bytesTotal': bytesTotal,
    'startedAt': startedAt, 'finishedAt': finishedAt,
  };

  factory SyncRunStatus.fromJson(Map<String, dynamic> j) => SyncRunStatus(
    running: j['running'] ?? false, phase: '${j['phase'] ?? 'Idle'}', current: j['current'],
    error: j['error'], message: j['message'], scannedSource: j['scannedSource'] ?? 0,
    scannedDestination: j['scannedDestination'] ?? 0, totalFiles: j['totalFiles'] ?? 0,
    totalBytes: j['totalBytes'] ?? 0, newFiles: j['newFiles'] ?? 0, updatedFiles: j['updatedFiles'] ?? 0,
    deletedFiles: j['deletedFiles'] ?? 0, unchangedFiles: j['unchangedFiles'] ?? 0,
    completed: j['completed'] ?? 0, failed: j['failed'] ?? 0, bytesDone: j['bytesDone'] ?? 0,
    bytesTotal: j['bytesTotal'] ?? 0, startedAt: j['startedAt'] ?? 0, finishedAt: j['finishedAt'] ?? 0,
  );

  static SyncRunStatus load(SharedPreferences p, String id) {
    final raw = p.getString('$kSyncRunPrefix$id');
    if (raw == null) return SyncRunStatus();
    try { return SyncRunStatus.fromJson(Map<String, dynamic>.from(jsonDecode(raw))); } catch (_) { return SyncRunStatus(); }
  }

  Future<void> save(SharedPreferences p, String id) =>
      p.setString('$kSyncRunPrefix$id', jsonEncode(toJson()));
}
