import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_client.dart';
import '../../core/util.dart';
import '../../core/vaulton.dart';
import '../transfers/transfer_engine.dart';
import '../transfers/transfer_models.dart';
import 'sync_models.dart';

typedef AlbumInfo = ({String id, String name, int count});

Future<bool> requestPhotoPermission() async => (await PhotoManager.requestPermissionExtend()).hasAccess;

Future<List<AlbumInfo>> listAlbums() async {
  if (!await requestPhotoPermission()) return [];
  final paths = await PhotoManager.getAssetPathList(type: RequestType.common, onlyAll: false);
  final out = <AlbumInfo>[];
  for (final a in paths) {
    out.add((id: a.id, name: a.name, count: await a.assetCountAsync));
  }
  return out;
}

Future<File> _doneFile() async {
  final d = await getApplicationSupportDirectory();
  return File(p.join(d.path, 'photo_sync_done.json'));
}

Future<Set<String>> _loadDone() async {
  try {
    final f = await _doneFile();
    if (await f.exists()) return Set<String>.from(jsonDecode(await f.readAsString()) as List);
  } catch (_) {}
  return <String>{};
}

Future<void> _saveDone(Set<String> s) async => (await _doneFile()).writeAsString(jsonEncode(s.toList()));

Future<void> resetSyncHistory(SharedPreferences prefs) async {
  final f = await _doneFile();
  if (await f.exists()) await f.delete();
  final st = SyncStatus.load(prefs)..totalSynced = 0;
  await st.save(prefs);
}

/// Incremental gallery backup. Safe to run from the UI or from WorkManager.
class PhotoSyncService {
  PhotoSyncService(this.api, this.prefs);
  final ApiClient api;
  final SharedPreferences prefs;

  /// Returns true when it stopped early (time budget) and should be continued.
  Future<bool> run({Duration budget = const Duration(minutes: 8)}) async {
    await prefs.reload();
    final s = SyncSettings.load(prefs);
    final prev = SyncStatus.load(prefs);
    if (prev.isLive) return false; // another run is already active
    final st = SyncStatus(running: true, totalSynced: prev.totalSynced, lastRun: prev.lastRun);
    if (s.pointId == null) {
      st..running = false..error = 'Choose a destination data point first.';
      await st.save(prefs);
      return false;
    }
    await st.save(prefs);
    final started = DateTime.now();
    final engine = TransferEngine(api);
    final v = Vaulton(api);
    final done = await _loadDone();
    var sinceSave = 0;
    var more = false;
    try {
      if (!await requestPhotoPermission()) throw ApiException('Photo library permission was not granted.');
      final albums = await PhotoManager.getAssetPathList(
        type: s.includeVideos ? RequestType.common : RequestType.image,
        onlyAll: s.albumIds.isEmpty,
        filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
      );
      final targets = s.albumIds.isEmpty ? albums : albums.where((a) => s.albumIds.contains(a.id)).toList();
      outer:
      for (final album in targets) {
        var page = 0;
        while (true) {
          final assets = await album.getAssetListPaged(page: page++, size: 100);
          if (assets.isEmpty) break;
          for (final a in assets) {
            if (DateTime.now().difference(started) > budget) {
              more = true;
              break outer;
            }
            if (done.contains(a.id)) continue;
            try {
              final file = await a.originFile;
              if (file == null) {
                st.skipped++;
                continue;
              }
              final name = (a.title?.isNotEmpty ?? false) ? a.title! : p.basename(file.path);
              final dt = a.createDateTime;
              final dir = s.organizeByDate
                  ? joinPath(s.remoteDir, '${dt.year}/${dt.month.toString().padLeft(2, '0')}')
                  : s.remoteDir;
              var remote = joinPath(dir, name);
              final len = await file.length();
              final existing = await v.headSize(s.pointId!, remote);
              if (existing != null) {
                if (existing == len) {
                  done.add(a.id);
                  st.skipped++;
                  continue;
                }
                remote = joinPath(dir, '${p.basenameWithoutExtension(name)}_${a.id.hashCode.toRadixString(16)}${p.extension(name)}');
              }
              st.current = name;
              await st.save(prefs);
              final t = TransferTask(id: a.id, kind: TKind.upload, pointId: s.pointId!, remotePath: remote,
                  name: name, localPath: file.path, total: len, origin: 'photos');
              await engine.upload(t, onProgress: (_, _) {});
              done.add(a.id);
              st.uploaded++;
              st.totalSynced = done.length;
              if (++sinceSave >= 15) {
                sinceSave = 0;
                await _saveDone(done);
                await st.save(prefs);
              }
            } on ApiException catch (e) {
              if (e.status == 401 || e.status == 403 || e.status == null) rethrow; // stop: auth/network problem
              st.failed++;
              st.error = e.message;
            } catch (_) {
              st.failed++;
            }
          }
        }
      }
    } on ApiException catch (e) {
      st.error = e.message;
      more = true; // retry later
    } catch (e) {
      st.error = '$e';
    }
    await _saveDone(done);
    st
      ..running = false
      ..current = null
      ..more = more
      ..totalSynced = done.length
      ..lastRun = DateTime.now().millisecondsSinceEpoch;
    await st.save(prefs);
    return more;
  }
}
