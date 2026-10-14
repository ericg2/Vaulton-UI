import 'package:shared_preferences/shared_preferences.dart';
import '../features/sync/sync_models.dart';

class SyncNotification {
  SyncNotification._();
  static Future<SyncNotification> start(SyncProfile profile) async => SyncNotification._();
  void progress(SyncRunStatus s) {}
  Future<void> finish(SharedPreferences prefs, {bool cancelled = false}) async {}
}

bool get backgroundSupported => false;
Future<void> initBackground() async {}
Future<void> scheduleDrain() async {}
Future<void> configurePhotoSync(SyncSettings s) async {}
Future<void> triggerPhotoSyncNow() async {}

Future<void> startBackgroundUpdateDownload({required String packageUrl, required String checksumUrl, required String fileName, required String version}) async { throw UnsupportedError('Background updates are not supported on this platform.'); }
Future<Map<String, Object?>> readBackgroundUpdateState() async => {'status': 'idle'};
Future<void> triggerSyncNow({String? profileId}) async {}
Future<void> cancelSyncNow(String profileId) async {}
Future<void> configureSyncSchedules(List<SyncProfile> profiles) async {}
