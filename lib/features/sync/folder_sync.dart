import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/util.dart';
import '../../platform/local_files.dart';
import '../transfers/transfer_manager.dart';
import 'sync_models.dart';

/// One-way folder mirror: uploads new/changed files through the transfer queue.
/// Returns how many uploads were queued.
Future<int> runFolderPair(FolderPair pair, SharedPreferences prefs, TransferManager mgr) async {
  if (!localFiles.supportsFilesystem) return 0;
  final key = 'folder_state_${pair.id}';
  Map<String, dynamic> state = {};
  try {
    state = Map<String, dynamic>.from(jsonDecode(prefs.getString(key) ?? '{}'));
  } catch (_) {}
  var queued = 0;
  final entries = await localFiles.listRecursive(pair.localDir);
  for (final e in entries) {
    final sig = '${e.size}:${e.modified.millisecondsSinceEpoch}';
    if (state[e.relative] == sig) continue;
    final t = mgr.addUpload(
      pointId: pair.pointId,
      remotePath: joinPath(pair.remoteDir, e.relative),
      localPath: e.path,
      size: e.size,
      origin: 'folder',
      overwrite: true,
    );
    state[e.relative] = sig;
    if (t != null) queued++;
  }
  await prefs.setString(key, jsonEncode(state));
  pair.lastRun = DateTime.now().millisecondsSinceEpoch;
  return queued;
}

Future<void> resetFolderState(SharedPreferences prefs, FolderPair pair) => prefs.remove('folder_state_${pair.id}');
