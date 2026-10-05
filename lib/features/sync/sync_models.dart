import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const kSyncSettings = 'sync_settings';
const kSyncStatus = 'sync_status';
const kFolderPairs = 'folder_pairs';

class SyncSettings {
  SyncSettings({
    this.enabled = false,
    this.pointId,
    this.remoteDir = '/Camera Backup',
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.includeVideos = true,
    this.organizeByDate = true,
    this.intervalMinutes = 60,
    List<String>? albumIds,
  }) : albumIds = albumIds ?? [];

  bool enabled, wifiOnly, chargingOnly, includeVideos, organizeByDate;
  String? pointId;
  String remoteDir;
  int intervalMinutes;
  List<String> albumIds; // empty = all photos

  Map<String, dynamic> toJson() => {
        'enabled': enabled, 'pointId': pointId, 'remoteDir': remoteDir, 'wifiOnly': wifiOnly,
        'chargingOnly': chargingOnly, 'includeVideos': includeVideos, 'organizeByDate': organizeByDate,
        'intervalMinutes': intervalMinutes, 'albumIds': albumIds,
      };

  factory SyncSettings.fromJson(Map<String, dynamic> j) => SyncSettings(
        enabled: j['enabled'] ?? false,
        pointId: j['pointId'],
        remoteDir: j['remoteDir'] ?? '/Camera Backup',
        wifiOnly: j['wifiOnly'] ?? true,
        chargingOnly: j['chargingOnly'] ?? false,
        includeVideos: j['includeVideos'] ?? true,
        organizeByDate: j['organizeByDate'] ?? true,
        intervalMinutes: j['intervalMinutes'] ?? 60,
        albumIds: List<String>.from(j['albumIds'] ?? const []),
      );

  static SyncSettings load(SharedPreferences p) {
    final raw = p.getString(kSyncSettings);
    if (raw == null) return SyncSettings();
    try {
      return SyncSettings.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return SyncSettings();
    }
  }

  Future<void> save(SharedPreferences p) => p.setString(kSyncSettings, jsonEncode(toJson()));
}

class SyncStatus {
  SyncStatus({this.running = false, this.uploaded = 0, this.skipped = 0, this.failed = 0, this.current,
      this.error, this.updatedAt = 0, this.lastRun = 0, this.more = false, this.totalSynced = 0});
  bool running, more;
  int uploaded, skipped, failed, updatedAt, lastRun, totalSynced;
  String? current, error;

  Map<String, dynamic> toJson() => {
        'running': running, 'uploaded': uploaded, 'skipped': skipped, 'failed': failed, 'current': current,
        'error': error, 'updatedAt': updatedAt, 'lastRun': lastRun, 'more': more, 'totalSynced': totalSynced,
      };

  factory SyncStatus.fromJson(Map<String, dynamic> j) => SyncStatus(
        running: j['running'] ?? false, uploaded: j['uploaded'] ?? 0, skipped: j['skipped'] ?? 0,
        failed: j['failed'] ?? 0, current: j['current'], error: j['error'], updatedAt: j['updatedAt'] ?? 0,
        lastRun: j['lastRun'] ?? 0, more: j['more'] ?? false, totalSynced: j['totalSynced'] ?? 0);

  static SyncStatus load(SharedPreferences p) {
    final raw = p.getString(kSyncStatus);
    if (raw == null) return SyncStatus();
    try {
      return SyncStatus.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return SyncStatus();
    }
  }

  Future<void> save(SharedPreferences p) {
    updatedAt = DateTime.now().millisecondsSinceEpoch;
    return p.setString(kSyncStatus, jsonEncode(toJson()));
  }

  bool get isLive => running && DateTime.now().millisecondsSinceEpoch - updatedAt < 60000;
}

/// A local folder mirrored (one-way, upload) into a data point. Desktop only.
class FolderPair {
  FolderPair({required this.id, required this.localDir, required this.pointId, required this.remoteDir,
      this.enabled = true, this.intervalMinutes = 15, this.lastRun = 0});
  final String id, localDir, pointId, remoteDir;
  bool enabled;
  int intervalMinutes, lastRun;

  Map<String, dynamic> toJson() => {'id': id, 'localDir': localDir, 'pointId': pointId, 'remoteDir': remoteDir,
        'enabled': enabled, 'intervalMinutes': intervalMinutes, 'lastRun': lastRun};
  factory FolderPair.fromJson(Map<String, dynamic> j) => FolderPair(id: j['id'], localDir: j['localDir'], pointId: j['pointId'],
      remoteDir: j['remoteDir'], enabled: j['enabled'] ?? true, intervalMinutes: j['intervalMinutes'] ?? 15, lastRun: j['lastRun'] ?? 0);

  static List<FolderPair> loadAll(SharedPreferences p) {
    final raw = p.getString(kFolderPairs);
    if (raw == null) return [];
    try {
      return [for (final j in jsonDecode(raw) as List) FolderPair.fromJson(Map<String, dynamic>.from(j))];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(SharedPreferences p, List<FolderPair> l) =>
      p.setString(kFolderPairs, jsonEncode([for (final f in l) f.toJson()]));
}
