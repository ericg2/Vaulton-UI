import 'models.dart';

/// Validates a Data Folder encryption password using Unicode scalar values,
/// matching the API and Rust KDF boundary.
String? validateDataFolderEncryptionPassword(
  String password, {
  String emptyMessage = 'Enter a password.',
}) {
  if (password.trim().isEmpty) return emptyMessage;
  final length = password.runes.length;
  if (length > 1024) return 'Use 1024 characters or fewer.';
  if (length < 12) return 'Use at least 12 characters.';
  return null;
}


/// Whether a Data Folder can be used by an immediate operation right now.
bool canUseDataFolderNow(Point point) =>
    !point.isEncrypted || point.isUnlocked;

/// Whether a Data Folder can be selected for a recurring schedule.
// Schedules never store folder credentials. They may target encrypted folders,
// but the folder must be unlocked when each scheduled job actually runs.
bool canScheduleDataFolder(Point point) => true;
