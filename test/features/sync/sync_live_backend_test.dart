import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vaulton/core/api_client.dart';
import 'package:vaulton/core/session.dart';
import 'package:vaulton/core/vaulton.dart';
import 'package:vaulton/features/sync/sync_models.dart';
import 'package:vaulton/features/sync/sync_service.dart';

void main() {
  final password = Platform.environment['VAULTON_TEST_PASSWORD'];
  final pointId = Platform.environment['VAULTON_TEST_POINT_ID'];

  test(
    'plans and applies add, update, and mirror-delete changes against Vaulton',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final session = SessionStore();
      final api = ApiClient(session);
      final vaulton = Vaulton(api);
      final tokens = await vaulton.signIn('admin', password!);
      session
        ..accessToken = tokens.access
        ..refreshToken = tokens.refresh
        ..expiresAt = tokens.expiresAt;

      final sourceDir = await Directory.systemTemp.createTemp(
        'vaulton-sync-source-',
      );
      final remoteDir =
          '/sync-verification-${DateTime.now().millisecondsSinceEpoch}';
      final sourceFile = File(
        '${sourceDir.path}${Platform.pathSeparator}sample.txt',
      );
      final profile = SyncProfile(
        id: 'sync-live-test',
        name: 'Live Sync Test',
        sourceKind: 'path',
        sourceLocation: sourceDir.path,
        sourceLabel: 'Live Test Source',
        pointId: pointId!,
        remoteDir: remoteDir,
        deleteExtras: true,
      );

      try {
        await vaulton.mkdir(pointId, remoteDir);

        await sourceFile.writeAsString('first version');
        final additions = await buildSyncPlan(api, profile, prefs);
        expect(additions.newFiles, 1);
        await applySyncPlan(api, profile, additions, prefs);
        expect(
          (await vaulton.list(pointId, remoteDir)).items.map((e) => e.name),
          contains('sample.txt'),
        );

        await sourceFile.writeAsString('second version with different content');
        final updates = await buildSyncPlan(api, profile, prefs);
        expect(updates.updatedFiles, 1);
        await applySyncPlan(api, profile, updates, prefs);

        await sourceFile.delete();
        final deletions = await buildSyncPlan(api, profile, prefs);
        expect(deletions.deletedFiles, 1);
        await applySyncPlan(api, profile, deletions, prefs);
        expect((await vaulton.list(pointId, remoteDir)).items, isEmpty);
      } finally {
        await sourceDir.delete(recursive: true);
        api.dio.close(force: true);
      }
    },
    skip:
        password == null ||
            password.isEmpty ||
            pointId == null ||
            pointId.isEmpty
        ? 'Set VAULTON_TEST_PASSWORD and VAULTON_TEST_POINT_ID to run against a disposable local backend.'
        : false,
  );
}
