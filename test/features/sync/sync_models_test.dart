import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/features/sync/sync_models.dart';

void main() {
  group('SyncProfile schedule migration', () {
    Map<String, dynamic> legacyProfile({int intervalMinutes = 60}) => {
      'id': 'sync-1',
      'name': 'Documents',
      'sourceKind': 'path',
      'sourceLocation': '/home/user/Documents',
      'sourceLabel': 'Documents',
      'pointId': 'point-1',
      'remoteDir': '/Documents',
      'intervalMinutes': intervalMinutes,
    };

    test('migrates old hourly profiles to an hourly cron schedule', () {
      final profile = SyncProfile.fromJson(legacyProfile());

      expect(profile.cron, '0 */1 * * *');
      expect(profile.timeZone, isEmpty);
      expect(profile.skipIfRunning, isTrue);
    });

    test('migrates old interval profiles to cron expressions', () {
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 15)).cron,
        '*/15 * * * *',
      );
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 30)).cron,
        '*/30 * * * *',
      );
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 180)).cron,
        '0 */3 * * *',
      );
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 360)).cron,
        '0 */6 * * *',
      );
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 720)).cron,
        '0 */12 * * *',
      );
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 1440)).cron,
        '0 2 * * *',
      );
    });

    test('round trips the full schedule configuration', () {
      final original = SyncProfile.fromJson({
        ...legacyProfile(),
        'cron': '30 7 * * 1,3,5',
        'timeZone': 'America/New_York',
        'skipIfRunning': false,
        'enabled': false,
        'nextRun': 123456789,
      });

      final restored = SyncProfile.fromJson(original.toJson());

      expect(restored.cron, '30 7 * * 1,3,5');
      expect(restored.timeZone, 'America/New_York');
      expect(restored.skipIfRunning, isFalse);
      expect(restored.enabled, isFalse);
      expect(restored.nextRun, 123456789);
    });
  });

  group('SyncManifestEntry', () {
    test('round trips a content hash while reading older manifests', () {
      final entry = SyncManifestEntry(size: 42, modified: 1234, hash: 'abc123');
      final restored = SyncManifestEntry.fromJson(entry.toJson());

      expect(restored.size, 42);
      expect(restored.modified, 1234);
      expect(restored.hash, 'abc123');
      expect(
        SyncManifestEntry.fromJson({'size': 42, 'modified': 1234}).hash,
        isNull,
      );
    });
  });

  group('corrupted persistence', () {
    test('profile list loads empty for missing or corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        SyncProfile.loadAll(await SharedPreferences.getInstance()),
        isEmpty,
      );

      SharedPreferences.setMockInitialValues({kSyncProfiles: '["unclosed'});
      expect(
        SyncProfile.loadAll(await SharedPreferences.getInstance()),
        isEmpty,
      );

      SharedPreferences.setMockInitialValues({
        kSyncProfiles: '{"not":"a list"}',
      });
      expect(
        SyncProfile.loadAll(await SharedPreferences.getInstance()),
        isEmpty,
      );
    });

    test('run status loads idle for missing or corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({});
      var prefs = await SharedPreferences.getInstance();
      expect(SyncRunStatus.load(prefs, 'abc').running, isFalse);

      SharedPreferences.setMockInitialValues({
        '${kSyncRunPrefix}abc': '{bad json',
      });
      prefs = await SharedPreferences.getInstance();
      final status = SyncRunStatus.load(prefs, 'abc');
      expect(status.running, isFalse);
      expect(status.phase, 'Idle');
    });

    test('manifest loads empty for missing or corrupt JSON', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        loadSyncManifest(await SharedPreferences.getInstance(), 'abc'),
        isEmpty,
      );

      SharedPreferences.setMockInitialValues({
        '${kSyncManifestPrefix}abc': '[1,2',
      });
      expect(
        loadSyncManifest(await SharedPreferences.getInstance(), 'abc'),
        isEmpty,
      );
    });

    test('profile fills safe defaults for missing fields', () {
      final profile = SyncProfile.fromJson({'id': 'x', 'pointId': 'y'});

      expect(profile.name, 'Folder Sync');
      expect(profile.remoteDir, '/');
      expect(profile.sourceLabel, 'Source Folder');
      expect(profile.enabled, isTrue);
      expect(profile.deleteExtras, isTrue);
      expect(profile.cron, isNotEmpty);
      expect(profile.skipIfRunning, isTrue);
      expect(profile.wifiOnly, isTrue);
    });

    test('run status round trips progress without losing counts', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final status = SyncRunStatus(
        running: true,
        phase: 'Uploading New Files',
        bytesDone: 50,
        bytesTotal: 100,
        completed: 3,
        failed: 1,
      );
      await status.save(prefs, 'abc');

      final restored = SyncRunStatus.load(prefs, 'abc');
      expect(restored.running, isTrue);
      expect(restored.phase, 'Uploading New Files');
      expect(restored.bytesDone, 50);
      expect(restored.bytesTotal, 100);
      expect(restored.completed, 3);
      expect(restored.failed, 1);
    });
  });
}
