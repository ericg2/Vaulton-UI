import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/models.dart';

void main() {
  test('cloud refresh status is parsed without exposing credentials', () {
    final root = Root.fromJson({
      'id': 'cloud-id',
      'name': 'Drive',
      'userName': 'alice',
      'source': {'scheme': 'gdrive'},
      'maxBytes': 1024,
      'allocatedBytes': 0,
      'freeBytes': 1024,
      'isDataAllowed': true,
      'isRepoAllowed': true,
      'isOwner': true,
      'cloudTokenExpiresAt': '2026-11-13T12:00:00Z',
      'cloudTokenRefreshError': 'Reconnect this cloud location.',
    });

    expect(root.cloudTokenExpiresAt, DateTime.utc(2026, 11, 13, 12));
    expect(root.cloudTokenRefreshError, 'Reconnect this cloud location.');
  });

  test('cloud roots are private and local roots remain shareable', () {
    Root cloud = Root.fromJson({
      'id': 'cloud-id',
      'name': 'Drive',
      'userName': 'alice',
      'source': {'scheme': 'gdrive', 'root': ''},
      'maxBytes': 1024,
      'allocatedBytes': 0,
      'freeBytes': 1024,
      'isDataAllowed': true,
      'isRepoAllowed': true,
      'isOwner': true,
    });
    Root local = Root.fromJson({
      'id': 'local-id',
      'name': 'Local',
      'userName': 'alice',
      'source': {'scheme': 'fs', 'root': '/mnt/vaulton-data'},
      'maxBytes': 1024,
      'allocatedBytes': 0,
      'freeBytes': 1024,
      'isDataAllowed': true,
      'isRepoAllowed': true,
      'isOwner': true,
    });

    expect(cloud.isPrivateCloud, isTrue);
    expect(cloud.isLocal, isFalse);
    expect(local.isLocal, isTrue);
    expect(local.isPrivateCloud, isFalse);
  });
}
