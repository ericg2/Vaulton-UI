import '../features/sync/sync_models.dart';

bool get backgroundSupported => false;
Future<void> initBackground() async {}
Future<void> scheduleDrain() async {}
Future<void> configurePhotoSync(SyncSettings s) async {}
Future<void> triggerPhotoSyncNow() async {}
