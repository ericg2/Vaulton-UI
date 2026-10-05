import 'package:shared_preferences/shared_preferences.dart';

typedef AlbumInfo = ({String id, String name, int count});
Future<bool> requestPhotoPermission() async => false;
Future<List<AlbumInfo>> listAlbums() async => [];
Future<void> resetSyncHistory(SharedPreferences prefs) async {}
