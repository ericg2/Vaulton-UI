import '../features/sync/sync_models.dart';

bool get backgroundSupported => false;
Future<void> initBackground() async {}
Future<void> scheduleDrain() async {}
Future<void> configurePhotoSync(SyncSettings s) async {}
Future<void> triggerPhotoSyncNow() async {}

Future<void> startBackgroundUpdateDownload({required String packageUrl, required String checksumUrl, required String fileName, required String version}) async { throw UnsupportedError('Background updates are not supported on this platform.'); }
Future<Map<String, Object?>> readBackgroundUpdateState() async => {'status': 'idle'};
