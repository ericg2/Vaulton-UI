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
bool canUseDataFolderNow(Point point) => !point.isEncrypted || point.isUnlocked;

/// Whether a Data Folder can be selected for a recurring schedule.
/// Schedules never store folder credentials. They may target encrypted folders,
/// but the folder must be unlocked when each scheduled job actually runs.
bool canScheduleDataFolder(Point point) => true;

final _autoUnlockAttempts = <String, Future<Point>>{};

/// Tries the signed-in account password without prompting. Folders that use a
/// legacy password simply stay locked until the user unlocks them explicitly.
/// Failures are remembered for this app session so polling does not keep
/// retrying a password that does not belong to the folder.
Future<Point> tryAutoUnlockDataFolder(
  Vaulton vaulton,
  Point point,
  String? accountPassword,
) async {
  if (!point.isEncrypted || point.isUnlocked) return point;
  if (accountPassword == null || accountPassword.isEmpty) return point;
  final attempt = '${point.id}\u0000${accountPassword.hashCode}';
  final existing = _autoUnlockAttempts[attempt];
  if (existing != null) return existing;

  // Share an in-flight request between startup and page initialization. Keep
  // the completed result too, so a legacy password is not retried on every
  // refresh during this app session.
  final pending = vaulton.unlockData(point.id, accountPassword).then<Point>(
    (unlocked) => unlocked,
    onError: (_) => point,
  );
  _autoUnlockAttempts[attempt] = pending;
  return pending;
}

/// Auto-unlocks every encrypted Data Folder that uses the signed-in account
/// password. Used once when the app starts and when a folder list is loaded.
Future<void> autoUnlockAllDataFolders(
  Vaulton vaulton,
  String? accountPassword,
) async {
  if (accountPassword == null || accountPassword.isEmpty) return;
  try {
    String? cursor;
    do {
      final page = await vaulton.datas(cursor: cursor, limit: 100);
      for (final point in page.items) {
        await tryAutoUnlockDataFolder(vaulton, point, accountPassword);
      }
      cursor = page.hasMore ? page.nextCursor : null;
    } while (cursor != null);
  } catch (_) {
    // Startup must never fail because a folder could not be unlocked.
  }
}

/// Tries the signed-in account password first, then prompts for a password or
/// recovery key. Dialog credentials are cleared when the dialog closes or fails.
Future<bool> unlockDataFolderWithPrompt(
  BuildContext context, {
  required Vaulton vaulton,
  required Point point,
  String? accountPassword,
}) async {
  if (!point.isEncrypted || point.isUnlocked) return true;
  if (accountPassword != null && accountPassword.isNotEmpty) {
    try {
      await vaulton.unlockData(point.id, accountPassword);
      return true;
    } catch (_) {
      // Existing folders may still use a legacy, separate password.
    }
  }
  final unlocked = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UnlockDataFolderDialog(vaulton: vaulton, point: point),
  );
  return unlocked == true;
}

class _UnlockDataFolderDialog extends StatefulWidget {
  const _UnlockDataFolderDialog({required this.vaulton, required this.point});

  final Vaulton vaulton;
  final Point point;

  @override
  State<_UnlockDataFolderDialog> createState() =>
      _UnlockDataFolderDialogState();
}

class _UnlockDataFolderDialogState extends State<_UnlockDataFolderDialog> {
  final _password = TextEditingController();
  final _recoveryKey = TextEditingController();
  bool _useRecovery = false;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _password.clear();
    _recoveryKey.clear();
    _password.dispose();
    _recoveryKey.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_useRecovery) {
      if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(_recoveryKey.text.trim())) {
        setState(() => _error = 'Enter the 43-character recovery key.');
        return;
      }
    } else {
      final validation = validateDataFolderEncryptionPassword(_password.text);
      if (validation != null) {
        setState(() => _error = validation);
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      if (_useRecovery) {
        await widget.vaulton.recoverData(
          widget.point.id,
          _recoveryKey.text.trim(),
        );
      } else {
        await widget.vaulton.unlockData(widget.point.id, _password.text);
      }
      // Clear credentials before closing so they do not linger in memory.
      _password.clear();
      _recoveryKey.clear();
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _password.clear();
      _recoveryKey.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Unlock Data Folder'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_useRecovery)
                TextField(
                  controller: _recoveryKey,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 43,
                  decoration: const InputDecoration(
                    labelText: 'Recovery Key',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _submit(),
                )
              else
                TextField(
                  controller: _password,
                  autofocus: true,
                  obscureText: true,
                  maxLength: 1024,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _useRecovery = !_useRecovery;
                          _password.clear();
                          _recoveryKey.clear();
                          _error = '';
                        }),
                  child: Text(
                    _useRecovery ? 'Use Password' : 'Use Recovery Key',
                  ),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Unlocking…' : 'Unlock'),
          ),
        ],
      ),
    );
  }
}
