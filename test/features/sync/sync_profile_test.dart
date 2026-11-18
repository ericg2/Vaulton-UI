import 'package:flutter_test/flutter_test.dart';

import 'package:vaulton/features/sync/sync_models.dart';

SyncProfile profile(
  String id,
  String pointId,
  String remoteDir,
  List<SyncSourceSpec> sources, {
  bool deleteExtras = true,
}) =>
    SyncProfile(
      id: id,
      name: id,
      sourceKind: sources.first.kind,
      sourceLocation: sources.first.location,
      sourceLabel: sources.first.label,
      sources: sources,
      pointId: pointId,
      remoteDir: remoteDir,
      deleteExtras: deleteExtras,
    );

void main() {
  test('Legacy profiles load as a single source', () {
    final p = SyncProfile.fromJson({
      'id': 'one',
      'name': 'Photos',
      'sourceKind': 'path',
      'sourceLocation': '/camera',
      'sourceLabel': 'Camera',
      'pointId': 'vault',
      'remoteDir': '/Camera',
    });
    expect(p.sources.length, 1);
    expect(p.sources.first.location, '/camera');
    expect(p.toJson()['sources'][0]['location'], '/camera');
  });

  test('Multiple sources survive a save and load round trip', () {
    final p = profile('multi', 'vault', '/Merge', [
      const SyncSourceSpec(kind: 'path', location: '/camera', label: 'Camera'),
      const SyncSourceSpec(kind: 'path', location: '/phone', label: 'Phone'),
    ]);
    final loaded = SyncProfile.fromJson(p.toJson());
    expect(loaded.sources.map((s) => s.location), ['/camera', '/phone']);
    expect(loaded.sourceLocation, '/camera');
  });

  test('Rejects two syncs writing to the same destination folder', () {
    final first = profile('one', 'vault', '/Merge', [
      const SyncSourceSpec(kind: 'path', location: '/camera', label: 'Camera'),
    ]);
    final second = profile('two', 'vault', '/Merge/', [
      const SyncSourceSpec(kind: 'path', location: '/other', label: 'Other'),
    ]);
    expect(validateSyncProfile(second, [first]), contains('already used'));
  });

  test('Rejects nested destinations that mirror mode could wipe', () {
    final first = profile('one', 'vault', '/Merge', [
      const SyncSourceSpec(kind: 'path', location: '/camera', label: 'Camera'),
    ]);
    final nested = profile('two', 'vault', '/Merge/Camera', [
      const SyncSourceSpec(kind: 'path', location: '/phone', label: 'Phone'),
    ]);
    expect(validateSyncProfile(nested, [first]), isNotNull);
  });

  test('Allows the same input to go to two different destinations', () {
    final first = profile('one', 'vault', '/One', [
      const SyncSourceSpec(kind: 'path', location: '/camera', label: 'Camera'),
    ]);
    final second = profile('two', 'vault', '/Two', [
      const SyncSourceSpec(kind: 'path', location: '/camera', label: 'Camera'),
    ]);
    expect(validateSyncProfile(second, [first]), isNull);
  });

  test('Rejects duplicate source names inside one profile', () {
    final p = profile('multi', 'vault', '/Merge', [
      const SyncSourceSpec(kind: 'path', location: '/camera', label: 'Camera'),
      const SyncSourceSpec(kind: 'path', location: '/phone', label: 'Camera'),
    ]);
    expect(validateSyncProfile(p, const []), contains('different name'));
  });
}
