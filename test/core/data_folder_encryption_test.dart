import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/models.dart';

void main() {
  group('Point Data Folder encryption state', () {
    test('parses encrypted and locked state', () {
      final point = Point.fromJson({
        'id': 'point-id',
        'rootId': 'root-id',
        'name': 'Private files',
        'maxBytes': 1024,
        'usedBytes': 12,
        'isReady': false,
        'isError': false,
        'isEncrypted': true,
        'isUnlocked': false,
      });

      expect(point.isEncrypted, isTrue);
      expect(point.isUnlocked, isFalse);
      expect(point.recoveryKey, isNull);
    });

    test('defaults encrypted points without live state to locked', () {
      final point = Point.fromJson({
        'id': 'point-id',
        'rootId': 'root-id',
        'name': 'Private files',
        'maxBytes': 1024,
        'usedBytes': 0,
        'isReady': false,
        'isError': false,
        'isEncrypted': true,
      });

      expect(point.isEncrypted, isTrue);
      expect(point.isUnlocked, isFalse);
    });

    test('defaults legacy and unencrypted points to accessible', () {
      final point = Point.fromJson({
        'id': 'point-id',
        'rootId': 'root-id',
        'name': 'Documents',
        'maxBytes': 1024,
        'usedBytes': 12,
        'isReady': true,
        'isError': false,
      });

      expect(point.isEncrypted, isFalse);
      expect(point.isUnlocked, isTrue);
    });

    test('reads one-time recovery key from creation response', () {
      final point = Point.fromJson({
        'id': 'point-id',
        'rootId': 'root-id',
        'name': 'Private files',
        'maxBytes': 1024,
        'usedBytes': 0,
        'isReady': true,
        'isError': false,
        'isEncrypted': true,
        'isUnlocked': true,
        'recoveryKey': 'one-time-secret',
      });

      expect(point.recoveryKey, 'one-time-secret');
    });
  });
}
