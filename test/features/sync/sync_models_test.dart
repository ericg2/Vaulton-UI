import 'package:flutter_test/flutter_test.dart';
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
      expect(profile.timeZone, 'UTC');
      expect(profile.skipIfRunning, isTrue);
    });

    test('migrates old minute-based profiles to cron expressions', () {
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 15)).cron,
        '*/15 * * * *',
      );
      expect(
        SyncProfile.fromJson(legacyProfile(intervalMinutes: 30)).cron,
        '*/30 * * * *',
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
}
