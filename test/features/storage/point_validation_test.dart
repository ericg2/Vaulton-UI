import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/features/storage/point_validation.dart';

void main() {
  group('Backup vault password validation', () {
    test('requires a non-empty password', () {
      expect(validateBackupVaultPassword(''), 'Enter a password.');
      expect(validateBackupVaultPassword('   '), 'Enter a password.');
    });

    test('requires at least eight characters', () {
      expect(
        validateBackupVaultPassword('short'),
        'Use at least 8 characters.',
      );
    });

    test('accepts a password with at least eight characters', () {
      expect(validateBackupVaultPassword('vault-pass'), isNull);
    });
  });
}
