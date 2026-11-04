import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/core/data_folder_encryption.dart';
import 'package:vaulton/core/models.dart';

void main() {
  group('Data Folder encryption password validation', () {
    test('rejects blank and whitespace-only passwords', () {
      expect(validateDataFolderEncryptionPassword(''), 'Enter a password.');
      expect(
        validateDataFolderEncryptionPassword('            '),
        'Enter a password.',
      );
    });

    test('counts Unicode scalar values like the API and Rust implementation', () {
      expect(
        validateDataFolderEncryptionPassword('😀😀😀😀😀😀'),
        'Use at least 12 characters.',
      );
      expect(validateDataFolderEncryptionPassword(List.filled(12, '😀').join()), isNull);
    });

    test('enforces the same Unicode scalar maximum length as the API', () {
      expect(
        validateDataFolderEncryptionPassword(List.filled(1024, '😀').join()),
        isNull,
      );
      expect(
        validateDataFolderEncryptionPassword(List.filled(1025, '😀').join()),
        'Use 1024 characters or fewer.',
      );
    });

    test('preserves a useful message for password changes', () {
      expect(
        validateDataFolderEncryptionPassword(
          ' ',
          emptyMessage: 'Enter a new password.',
        ),
        'Enter a new password.',
      );
    });
  });

  group('Data Folder operation eligibility', () {
    Point point({required bool encrypted, required bool unlocked}) => Point(
          id: 'point-id',
          rootId: 'root-id',
          name: 'Files',
          maxBytes: 4096,
          usedBytes: 0,
          isReady: true,
          isError: false,
          isEncrypted: encrypted,
          isUnlocked: unlocked,
        );

    test('immediate operations require encrypted folders to be unlocked', () {
      expect(canUseDataFolderNow(point(encrypted: false, unlocked: true)), isTrue);
      expect(canUseDataFolderNow(point(encrypted: true, unlocked: false)), isFalse);
      expect(canUseDataFolderNow(point(encrypted: true, unlocked: true)), isTrue);
    });

    test('recurring schedules never accept encrypted folders', () {
      expect(canScheduleDataFolder(point(encrypted: false, unlocked: true)), isTrue);
      expect(canScheduleDataFolder(point(encrypted: true, unlocked: false)), isFalse);
      expect(canScheduleDataFolder(point(encrypted: true, unlocked: true)), isFalse);
    });
  });

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

    test('parses pending encryption configuration synchronization', () {
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
        'encryptionSyncPending': true,
      });

      expect(point.encryptionSyncPending, isTrue);
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
