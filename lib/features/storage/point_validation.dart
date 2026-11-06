/// Validates the password required to create a backup vault.
String? validateBackupVaultPassword(String password) {
  if (password.trim().isEmpty) return 'Enter a password.';
  if (password.runes.length < 8) return 'Use at least 8 characters.';
  return null;
}
