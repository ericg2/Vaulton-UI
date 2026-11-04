import 'package:flutter/material.dart';

import 'models.dart';
import 'vaulton.dart';

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
/// Schedules never store folder credentials. They may target encrypted folders,
/// but the folder must be unlocked when each scheduled job actually runs.
bool canScheduleDataFolder(Point point) => true;

/// Prompts for a folder password or recovery key and clears both credentials
/// from the controllers whenever the dialog closes or a request fails.
Future<bool> unlockDataFolderWithPrompt(
  BuildContext context, {
  required Vaulton vaulton,
  required Point point,
}) async {
  final password = TextEditingController();
  final recoveryKey = TextEditingController();
  var useRecovery = false;
  var busy = false;
  var error = '';

  try {
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('Unlock Data Folder'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (useRecovery)
                  TextField(
                    controller: recoveryKey,
                    autofocus: true,
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 128,
                    decoration: const InputDecoration(
                      labelText: 'Recovery Key',
                      counterText: '',
                    ),
                    onSubmitted: (_) => submit(),
                  )
                else
                  TextField(
                    controller: password,
                    autofocus: true,
                    obscureText: true,
                    maxLength: 1024,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      counterText: '',
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setDialogState(() {
                              useRecovery = !useRecovery;
                              password.clear();
                              recoveryKey.clear();
                              error = '';
                            }),
                    child: Text(
                      useRecovery ? 'Use Password' : 'Use Recovery Key',
                    ),
                  ),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? 'Unlocking…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
    return unlocked == true;
  } finally {
    password.clear();
    recoveryKey.clear();
    password.dispose();
    recoveryKey.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (useRecovery) {
      if (recoveryKey.text.trim().isEmpty) {
        setError('Enter your recovery key.');
        return;
      }
    } else {
      final validation = validateDataFolderEncryptionPassword(password.text);
      if (validation != null) {
        setError(validation);
        return;
      }
    }

    setDialogBusy(true);
    try {
      if (useRecovery) {
        await vaulton.recoverData(point.id, recoveryKey.text.trim());
      } else {
        await vaulton.unlockData(point.id, password.text);
      }
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      password.clear();
      recoveryKey.clear();
      setError(e.toString());
      setDialogBusy(false);
    }
  }

  void setError(String value) {
    // The dialog builder owns the state setter; submit is invoked only while
    // that dialog is mounted.
    error = value;
  }

  void setDialogBusy(bool value) {
    busy = value;
  }
}
